import Foundation

/// Where bookmarks come from. The mock lives in memory; a server-backed
/// implementation can replace it without touching the views.
protocol BookmarkService {
    func fetchBookmarks() async throws -> [Bookmark]
    func updateBookmark(_ bookmark: Bookmark) async throws
    func deleteBookmark(id: Bookmark.ID) async throws

    func fetchCollections() async throws -> [BookmarkCollection]
    func createCollection(named name: String) async throws -> BookmarkCollection
    func updateCollection(_ collection: BookmarkCollection) async throws
    /// Deletes the collection and removes it from every post; the posts themselves stay.
    func deleteCollection(id: BookmarkCollection.ID) async throws
}

final class MockBookmarkService: BookmarkService {
    private var bookmarks = MockData.bookmarks
    private var collections = MockData.collections

    func fetchBookmarks() async throws -> [Bookmark] {
        bookmarks
    }

    func updateBookmark(_ bookmark: Bookmark) async throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index] = bookmark
    }

    func deleteBookmark(id: Bookmark.ID) async throws {
        bookmarks.removeAll { $0.id == id }
    }

    func fetchCollections() async throws -> [BookmarkCollection] {
        collections
    }

    func createCollection(named name: String) async throws -> BookmarkCollection {
        let collection = BookmarkCollection(id: UUID().uuidString, name: name)
        collections.append(collection)
        return collection
    }

    func updateCollection(_ collection: BookmarkCollection) async throws {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[index] = collection
    }

    func deleteCollection(id: BookmarkCollection.ID) async throws {
        collections.removeAll { $0.id == id }
        for index in bookmarks.indices {
            bookmarks[index].collectionIDs.remove(id)
        }
    }
}
