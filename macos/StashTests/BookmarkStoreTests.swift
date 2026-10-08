import Foundation
import Testing
@testable import Stash

@Suite("BookmarkStore")
struct BookmarkStoreTests {
    let library = TemporaryLibrary()

    private func store(with bookmarks: [Bookmark]) async throws -> BookmarkStore {
        let service = library.service()
        for bookmark in bookmarks {
            try await service.saveBookmark(bookmark)
        }
        let store = BookmarkStore(service: service)
        await store.load()
        return store
    }

    @Test func `adds a post saved in the browser`() async throws {
        let store = try await store(with: [])

        let accepted = await store.ingest(.sample(id: "1", text: "new"))

        #expect(accepted)
        #expect(store.bookmarks.map(\.id) == ["1"])
        #expect(try await library.service().fetchBookmarks().map(\.id) == ["1"], "persisted")
    }

    @Test func `saving again refreshes content but keeps collections and the first save date`() async throws {
        let firstSave = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = Bookmark.sample(
            id: "1", text: "old", savedAt: firstSave, collectionIDs: ["design"], trashedAt: .now
        )
        let store = try await store(with: [existing])

        await store.ingest(.sample(id: "1", text: "edited", savedAt: .now))

        let merged = try #require(store.bookmark(id: "1"))
        #expect(merged.text == "edited")
        #expect(merged.collectionIDs == ["design"])
        #expect(merged.savedAt == firstSave)
        #expect(merged.trashedAt == nil, "saving again brings it back from Trash")
    }

    @Test func `removing in the browser moves the post to Trash`() async throws {
        let store = try await store(with: [.sample(id: "1")])

        await store.ingestRemoval(id: "1")

        #expect(store.bookmark(id: "1")?.isTrashed == true)
        #expect(store.bookmarks(in: .all, matching: "").isEmpty)
        #expect(store.bookmarks(in: .trash, matching: "").map(\.id) == ["1"])
    }

    @Test func `counts every sidebar item in one pass`() async throws {
        let store = try await store(with: [
            .sample(id: "1"),
            .sample(id: "2", collectionIDs: ["design"]),
            .sample(id: "3", collectionIDs: ["design", "photos"]),
            .sample(id: "4", collectionIDs: ["design"], trashedAt: .now),
        ])

        let counts = store.sidebarCounts

        #expect(counts[.all] == 3)
        #expect(counts[.inbox] == 1)
        #expect(counts[.trash] == 1)
        #expect(counts[.collection(id: "design")] == 2, "trashed posts don't count")
        #expect(counts[.collection(id: "photos")] == 1)
        for item in [SidebarItem.all, .inbox, .trash, .collection(id: "design"), .collection(id: "photos")] {
            #expect(counts[item, default: 0] == store.bookmarks(in: item, matching: "").count, "\(item)")
        }
    }

    @Test func `searches text and author`() async throws {
        let store = try await store(with: [.sample(id: "1", text: "Liquid Glass icons"), .sample(id: "2", text: "SQLite")])

        #expect(store.bookmarks(in: .all, matching: "glass").map(\.id) == ["1"])
        #expect(store.bookmarks(in: .all, matching: "test").count == 2, "author handle matches")
    }

    @Test func `names new collections without clashing`() async throws {
        let store = try await store(with: [])

        let first = await store.createCollection()
        let second = await store.createCollection()

        #expect(first?.name == "New Collection")
        #expect(second?.name == "New Collection 2")
    }
}
