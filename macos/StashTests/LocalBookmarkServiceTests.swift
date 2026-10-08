import Foundation
import Testing
@testable import Stash

@Suite("The library file")
struct LocalBookmarkServiceTests {
    let library = TemporaryLibrary()

    @Test func `starts empty when there's no file yet`() async throws {
        let service = library.service()

        #expect(try await service.fetchBookmarks().isEmpty)
        #expect(service.takeLaunchWarning() == nil)
    }

    @Test func `keeps what was saved across launches`() async throws {
        try await library.service().saveBookmark(.sample(id: "1", text: "first"))
        try await library.service().saveCollection(BookmarkCollection(id: "design", name: "Design"))

        let relaunched = library.service()
        #expect(try await relaunched.fetchBookmarks().map(\.text) == ["first"])
        #expect(try await relaunched.fetchCollections().map(\.name) == ["Design"])
    }

    @Test func `replaces a bookmark saved again under the same id`() async throws {
        let service = library.service()
        try await service.saveBookmark(.sample(id: "1", text: "old"))
        try await service.saveBookmark(.sample(id: "1", text: "new"))

        #expect(try await service.fetchBookmarks().map(\.text) == ["new"])
    }

    @Test func `hides deleted bookmarks but keeps a marker on disk for sync`() async throws {
        let service = library.service()
        try await service.saveBookmark(.sample(id: "1"))
        try await service.deleteBookmark(id: "1")

        #expect(try await library.service().fetchBookmarks().isEmpty)
        let snapshot = try StashJSON.decoder.decode(LibrarySnapshot.self, from: Data(contentsOf: library.fileURL))
        #expect(snapshot.bookmarks.first?.deletedAt != nil)
    }

    @Test func `deleting a collection takes it off every post but keeps the posts`() async throws {
        let service = library.service()
        try await service.saveCollection(BookmarkCollection(id: "design", name: "Design"))
        try await service.saveBookmark(.sample(id: "1", collectionIDs: ["design", "other"]))

        try await service.deleteCollection(id: "design")

        #expect(try await service.fetchCollections().isEmpty)
        #expect(try await service.fetchBookmarks().first?.collectionIDs == ["other"])
    }

    @Test func `sets an unreadable file aside instead of overwriting it`() async throws {
        try library.write("{ not json")

        let service = library.service()

        #expect(try await service.fetchBookmarks().isEmpty)
        #expect(service.takeLaunchWarning()?.contains("couldn't be read") == true)
        #expect(service.takeLaunchWarning() == nil, "warns once")
        let files = try library.filesInFolder()
        #expect(files.contains { $0.hasPrefix("library-unreadable-") })
        #expect(!files.contains("library.json"))
    }

    @Test func `keeps a newer library it can't decode at all, read-only, in place`() async throws {
        // A future format this version can't parse (here: bookmarks became an object).
        try library.write(#"{ "schemaVersion": 2, "bookmarks": { "byID": {} } }"#)
        let service = library.service()

        #expect(service.takeLaunchWarning()?.contains("newer version") == true)
        #expect(try await service.fetchBookmarks().isEmpty)
        await #expect(throws: LibraryError.self) {
            try await service.saveBookmark(.sample(id: "1"))
        }
        #expect(try library.filesInFolder() == ["library.json"], "not moved aside as unreadable")
    }

    @Test func `skips a media kind it doesn't know instead of failing the post`() async throws {
        try library.write("""
        { "schemaVersion": 1, "collections": [], "bookmarks": [{
          "id": "1", "url": "https://x.com/t/status/1", "author": { "name": "T", "handle": "t" },
          "postedAt": "2026-01-01T00:00:00Z", "savedAt": "2026-01-01T00:00:00Z",
          "media": [
            { "kind": "hologram", "url": "https://pbs.twimg.com/h.bin" },
            { "kind": "photo", "url": "https://pbs.twimg.com/p.jpg" }
          ]
        }] }
        """)

        let bookmarks = try await library.service().fetchBookmarks()

        #expect(bookmarks.first?.media.map(\.kind) == [.photo])
    }

    @Test func `opens a library from a newer version read-only`() async throws {
        try library.write(#"{ "schemaVersion": 99, "bookmarks": [], "collections": [] }"#)
        let service = library.service()

        #expect(service.takeLaunchWarning()?.contains("newer version") == true)
        await #expect(throws: LibraryError.self) {
            try await service.saveBookmark(.sample(id: "1"))
        }
        let untouched = try String(contentsOf: library.fileURL, encoding: .utf8)
        #expect(untouched.contains("99"))
    }
}
