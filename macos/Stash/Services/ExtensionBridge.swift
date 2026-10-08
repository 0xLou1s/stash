import Foundation
import Network

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
///     PUT    /v1/bookmarks/{id}    body: bookmark JSON
///     DELETE /v1/bookmarks/{id}
final class ExtensionBridge {
    /// Keep in sync with `APP_URL` in extension/src/lib/sync.ts.
    static let port: NWEndpoint.Port = 47811

    private let store: BookmarkStore
    private var listener: NWListener?

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
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    // Most likely another copy of Stash already has the port.
                    print("[Stash] Extension bridge stopped: \(error)")
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            print("[Stash] Couldn't start the extension bridge: \(error)")
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }

                var buffer = buffer
                if let data { buffer.append(data) }

                if let request = HTTPRequest(parsing: buffer) {
                    Task {
                        let response = await self.respond(to: request)
                        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    }
                } else if isComplete || error != nil || buffer.count > 20_000_000 {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    // MARK: - Routes

    private func respond(to request: HTTPRequest) async -> HTTPResponse {
        let origin = request.headers["origin"] ?? ""
        let fromExtension = origin.hasPrefix("chrome-extension://")
        var response = await route(request, trusted: fromExtension || origin.isEmpty)
        if fromExtension {
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Access-Control-Allow-Methods"] = "GET, PUT, DELETE, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "Content-Type"
        }
        return response
    }

    private func route(_ request: HTTPRequest, trusted: Bool) async -> HTTPResponse {
        let path = request.path.split(separator: "?").first.map(String.init) ?? ""
        let segments = path.split(separator: "/").map(String.init)

        if request.method == "OPTIONS" {
            return HTTPResponse(status: trusted ? 204 : 403)
        }

        if request.method == "GET", segments == ["v1", "health"] {
            return .json(["app": "Stash", "ok": true])
        }

        guard segments.count == 3, segments[0] == "v1", segments[1] == "bookmarks" else {
            return HTTPResponse(status: 404)
        }
        guard trusted else {
            return HTTPResponse(status: 403)
        }
        let id = segments[2]

        switch request.method {
        case "PUT":
            guard let bookmark = try? StashJSON.decoder.decode(Bookmark.self, from: request.body),
                  bookmark.id == id
            else {
                return HTTPResponse(status: 400)
            }
            return HTTPResponse(status: await store.ingest(bookmark) ? 204 : 500)

        case "DELETE":
            return HTTPResponse(status: await store.ingestRemoval(id: id) ? 204 : 500)

        default:
            return HTTPResponse(status: 405)
        }
    }
}

// MARK: - Minimal HTTP/1.1

private struct HTTPRequest {
    let method: String
    let path: String
    /// Lowercased names.
    let headers: [String: String]
    let body: Data

    /// Returns nil until `data` holds the full request (headers plus Content-Length bytes).
    init?(parsing data: Data) {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8)
        else { return nil }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }

        method = String(requestLine[0])
        path = String(requestLine[1])
        self.headers = headers
        body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: length)])
    }
}

private struct HTTPResponse {
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
