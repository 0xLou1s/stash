import Foundation
import Testing
@testable import Stash

/// Calls the bridge's request handler directly; no port is opened.
@Suite("Bridge routing and trust")
struct ExtensionBridgeTests {
    let library = TemporaryLibrary()

    private func bridge() async -> (ExtensionBridge, BookmarkStore) {
        let store = BookmarkStore(service: library.service())
        await store.load()
        return (ExtensionBridge(store: store), store)
    }

    private func request(
        _ method: String,
        _ path: String,
        origin: String? = "chrome-extension://abcdefghijklmnop",
        body: String = ""
    ) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let origin { headers["origin"] = origin }
        return HTTPRequest(method: method, path: path, headers: headers, body: Data(body.utf8))
    }

    private func postJSON(id: String, url: String = "https://x.com/t/status/1", mediaURL: String? = nil) -> String {
        let media = mediaURL.map { #"[{ "kind": "photo", "url": "\#($0)", "posterURL": null, "width": 1, "height": 1 }]"# } ?? "[]"
        return """
        { "id": "\(id)", "url": "\(url)", "author": { "name": "T", "handle": "t", "avatarURL": null },
          "text": "", "media": \(media), "postedAt": "2026-01-01T00:00:00.000Z", "savedAt": "2026-01-01T00:00:00.000Z" }
        """
    }

    @Test func `saves a post from the extension`() async {
        let (bridge, store) = await bridge()

        let response = await bridge.respond(to: request("PUT", "/v1/bookmarks/1", body: postJSON(id: "1")))

        #expect(response.status == 204)
        #expect(store.bookmark(id: "1") != nil)
    }

    @Test func `accepts local software that sends no origin`() async {
        let (bridge, _) = await bridge()

        let response = await bridge.respond(to: request("PUT", "/v1/bookmarks/1", origin: nil, body: postJSON(id: "1")))

        #expect(response.status == 204)
    }

    @Test(arguments: ["https://evil.example", "null", "http://localhost:3000"])
    func `refuses changes from web pages`(origin: String) async {
        let (bridge, store) = await bridge()

        let put = await bridge.respond(to: request("PUT", "/v1/bookmarks/1", origin: origin, body: postJSON(id: "1")))
        let delete = await bridge.respond(to: request("DELETE", "/v1/bookmarks/1", origin: origin))

        #expect(put.status == 403)
        #expect(delete.status == 403)
        #expect(store.bookmarks.isEmpty)
    }

    @Test(arguments: [
        ("file:///Applications/Calculator.app", nil),
        ("smb://evil.example/share", nil),
        ("http://x.com/t/status/1", nil),
        ("https://x.com.evil.example/t/status/1", nil),
        ("https://x.com/t/status/1", "https://evil.example/tracker.png"),
        ("https://x.com/t/status/1", "http://pbs.twimg.com/a.jpg"),
    ] as [(String, String?)])
    func `rejects posts whose links don't point at X`(url: String, mediaURL: String?) async {
        let (bridge, store) = await bridge()

        let response = await bridge.respond(
            to: request("PUT", "/v1/bookmarks/1", body: postJSON(id: "1", url: url, mediaURL: mediaURL))
        )

        #expect(response.status == 400)
        #expect(store.bookmarks.isEmpty)
    }

    @Test func `rejects a body whose id doesn't match the path`() async {
        let (bridge, _) = await bridge()

        let response = await bridge.respond(to: request("PUT", "/v1/bookmarks/2", body: postJSON(id: "1")))

        #expect(response.status == 400)
    }

    @Test func `sends no CORS headers, so other extensions' pages can't get through`() async {
        let (bridge, _) = await bridge()

        let preflight = await bridge.respond(to: request("OPTIONS", "/v1/bookmarks/1"))
        let health = await bridge.respond(to: request("GET", "/v1/health"))

        #expect(preflight.status != 204)
        #expect(preflight.headers.keys.allSatisfy { !$0.lowercased().hasPrefix("access-control") })
        #expect(health.headers.keys.allSatisfy { !$0.lowercased().hasPrefix("access-control") })
    }

    @Test func `answers health checks and unknown routes`() async {
        let (bridge, _) = await bridge()

        #expect(await bridge.respond(to: request("GET", "/v1/health")).status == 200)
        #expect(await bridge.respond(to: request("GET", "/v1/nope")).status == 404)
        #expect(await bridge.respond(to: request("PATCH", "/v1/bookmarks/1")).status == 405)
    }
}
