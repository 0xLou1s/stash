import Foundation

/// Where bookmarks come from. The mock lives in memory; a server-backed
/// implementation can replace it without touching the views.
protocol BookmarkService {
    func fetchBookmarks() async throws -> [Bookmark]
    func fetchCollections() async throws -> [BookmarkCollection]
    func updateBookmark(_ bookmark: Bookmark) async throws
    func deleteBookmark(id: Bookmark.ID) async throws
}

final class MockBookmarkService: BookmarkService {
    private var bookmarks = MockData.bookmarks

    func fetchBookmarks() async throws -> [Bookmark] {
        bookmarks
    }

    func fetchCollections() async throws -> [BookmarkCollection] {
        MockData.collections
    }

    func updateBookmark(_ bookmark: Bookmark) async throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index] = bookmark
    }

    func deleteBookmark(id: Bookmark.ID) async throws {
        bookmarks.removeAll { $0.id == id }
    }
}
