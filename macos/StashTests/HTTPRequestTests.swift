import Foundation
import Testing
@testable import Stash

@Suite("Parsing bridge requests")
struct HTTPRequestTests {
    private func parse(_ raw: String) -> HTTPRequest.ParseResult {
        HTTPRequest.parse(Data(raw.utf8))
    }

    private func complete(_ raw: String) throws -> HTTPRequest {
        guard case .complete(let request) = parse(raw) else {
            Issue.record("expected a complete request")
            throw CancellationError()
        }
        return request
    }

    @Test func `parses a complete request`() throws {
        let request = try complete(
            "PUT /v1/bookmarks/42 HTTP/1.1\r\nOrigin: chrome-extension://abc\r\nContent-Length: 2\r\n\r\n{}"
        )

        #expect(request.method == "PUT")
        #expect(request.pathSegments == ["v1", "bookmarks", "42"])
        #expect(request.headers["origin"] == "chrome-extension://abc", "header names are lowercased")
        #expect(request.body == Data("{}".utf8))
    }

    @Test(arguments: [
        "PUT /v1/bookmarks/42 HTTP/1.1\r\nContent-Length: 2",               // headers not finished
        "PUT /v1/bookmarks/42 HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\"",  // body still arriving
    ])
    func `waits for the rest of a partial request`(raw: String) {
        guard case .incomplete = parse(raw) else {
            Issue.record("expected incomplete")
            return
        }
    }

    @Test(arguments: [
        "PUT /v1/bookmarks/1 HTTP/1.1\r\nContent-Length: -1\r\n\r\n",                   // used to crash the app
        "PUT /v1/bookmarks/1 HTTP/1.1\r\nContent-Length: abc\r\n\r\n",
        "PUT /v1/bookmarks/1 HTTP/1.1\r\nContent-Length: \(HTTPRequest.maxBodyBytes + 1)\r\n\r\n",
        "GARBAGE\r\n\r\n",
    ])
    func `rejects malformed or oversized requests`(raw: String) {
        guard case .invalid = parse(raw) else {
            Issue.record("expected invalid")
            return
        }
    }

    @Test func `rejects headers that never end`() {
        let endless = "GET /v1/health HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPRequest.maxHeaderBytes)

        guard case .invalid = parse(endless) else {
            Issue.record("expected invalid")
            return
        }
    }

    @Test func `ignores the query string when routing`() throws {
        let request = try complete("GET /v1/health?probe=1 HTTP/1.1\r\n\r\n")

        #expect(request.pathSegments == ["v1", "health"])
        #expect(request.body.isEmpty)
    }
}
