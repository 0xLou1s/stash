import Foundation
import Network
import os

/// A tiny HTTP endpoint the Chrome extension sends saves to while the app is
/// running. It listens on 127.0.0.1 only, and refuses changes from web pages:
/// browsers always attach a page's origin to these requests and pages can't
/// fake `chrome-extension://`. Requests with no origin at all can only come
/// from software on this Mac, which could edit the library file anyway.
///
/// The routes match the planned cloud API, so moving the extension to the
/// cloud means changing its base URL, not its sync code:
///
///     GET    /v1/health
///     PUT    /v1/bookmarks/{id}    body: bookmark JSON (links must point at X)
///     DELETE /v1/bookmarks/{id}
final class ExtensionBridge {
    /// Keep in sync with `APP_URL` in extension/src/lib/sync.ts.
    static let port: NWEndpoint.Port = 47811

    private let store: BookmarkStore
    private var listener: NWListener?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Stash", category: "ExtensionBridge")

    init(store: BookmarkStore) {
        self.store = store
    }

    func start() {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters, on: Self.port)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [logger] state in
                if case .failed(let error) = state {
                    // Most likely another copy of Stash already has the port.
                    logger.error("Extension bridge stopped: \(error, privacy: .public)")
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            logger.error("Couldn't start the extension bridge: \(error, privacy: .public)")
        }
    }

    // MARK: - Connections

    /// A request has this long to arrive in full, so idle or trickling
    /// connections can't pile up.
    private static let requestTimeout: Duration = .seconds(10)

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
        Task {
            try? await Task.sleep(for: Self.requestTimeout)
            connection.cancel() // No-op if the connection already finished.
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }

                var buffer = buffer
                if let data { buffer.append(data) }

                switch HTTPRequest.parse(buffer) {
                case .complete(let request):
                    Task {
                        let response = await self.respond(to: request)
                        Self.send(response, on: connection)
                    }
                case .invalid:
                    Self.send(HTTPResponse(status: 400), on: connection)
                case .incomplete where isComplete || error != nil:
                    connection.cancel()
                case .incomplete:
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private static func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Routes

    func respond(to request: HTTPRequest) async -> HTTPResponse {
        let origin = request.headers["origin"] ?? ""
        // Pages always send their origin; no origin means software on this Mac.
        // No CORS headers are sent: Stash's extension has host permission for
        // 127.0.0.1 and doesn't need them, and sending them would let other
        // extensions' pages through the browser's cross-origin checks.
        return await route(request, trusted: origin.hasPrefix("chrome-extension://") || origin.isEmpty)
    }

    private func route(_ request: HTTPRequest, trusted: Bool) async -> HTTPResponse {
        let segments = request.pathSegments

        if request.method == "GET", segments == ["v1", "health"] {
            return .json(["app": "Stash", "ok": true])
        }

        guard segments.count == 3, segments[0] == "v1", segments[1] == "bookmarks" else {
            return HTTPResponse(status: 404)
        }
        guard trusted else {
            return HTTPResponse(status: 403)
        }

        switch request.method {
        case "PUT": return await saveBookmark(id: segments[2], json: request.body)
        case "DELETE": return await removeBookmark(id: segments[2])
        default: return HTTPResponse(status: 405)
        }
    }

    private func saveBookmark(id: Bookmark.ID, json: Data) async -> HTTPResponse {
        guard let bookmark = try? StashJSON.decoder.decode(Bookmark.self, from: json),
              bookmark.id == id,
              bookmark.hasTrustedLinks
        else {
            return HTTPResponse(status: 400)
        }
        return HTTPResponse(status: await store.ingest(bookmark) ? 204 : 500)
    }

    private func removeBookmark(id: Bookmark.ID) async -> HTTPResponse {
        HTTPResponse(status: await store.ingestRemoval(id: id) ? 204 : 500)
    }
}

// MARK: - Minimal HTTP/1.1

struct HTTPRequest {
    let method: String
    let path: String
    /// Lowercased names.
    let headers: [String: String]
    let body: Data

    /// "/v1/bookmarks/123?x=1" → ["v1", "bookmarks", "123"]
    var pathSegments: [String] {
        let path = path.split(separator: "?", maxSplits: 1).first ?? ""
        return path.split(separator: "/").map(String.init)
    }

    enum ParseResult {
        /// Keep reading.
        case incomplete
        case complete(HTTPRequest)
        /// Malformed or too large; answer 400 and close.
        case invalid
    }

    /// A bookmark is a few KB; these leave plenty of room and cap what one connection can buffer.
    static let maxHeaderBytes = 16 * 1024
    static let maxBodyBytes = 1024 * 1024

    static func parse(_ data: Data) -> ParseResult {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderBytes ? .invalid : .incomplete
        }
        guard data.distance(from: data.startIndex, to: headerEnd.lowerBound) <= maxHeaderBytes,
              let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8)
        else { return .invalid }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length: Int
        if let declared = headers["content-length"] {
            guard let value = Int(declared), (0...maxBodyBytes).contains(value) else { return .invalid }
            length = value
        } else {
            length = 0
        }

        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return .incomplete }

        return .complete(HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: Data(data[bodyStart..<data.index(bodyStart, offsetBy: length)])
        ))
    }
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String] = [:]
    var body = Data()

    static func json(_ object: [String: Any]) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: body)
    }

    func serialized() -> Data {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
