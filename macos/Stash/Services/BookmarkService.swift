import Foundation

/// Where the library is stored. Today that's `LocalBookmarkService` (a file on
/// this Mac). Cloud sync will run alongside it, comparing `updatedAt` and
/// `deletedAt` on each record, so the views and the store don't change.
protocol BookmarkService {
    /// Every bookmark that isn't deleted, including ones in Trash.
    func fetchBookmarks() async throws -> [Bookmark]
    /// Inserts or replaces by id.
    func saveBookmark(_ bookmark: Bookmark) async throws
    /// Deletes for good (leaves a hidden `deletedAt` marker for sync).
    func deleteBookmark(id: Bookmark.ID) async throws

    func fetchCollections() async throws -> [BookmarkCollection]
    /// Inserts or replaces by id.
    func saveCollection(_ collection: BookmarkCollection) async throws
    /// Deletes the collection and removes it from every post; the posts themselves stay.
    func deleteCollection(id: BookmarkCollection.ID) async throws

    /// A problem found while opening the library that the user should hear about once.
    func takeLaunchWarning() -> String?
}

extension BookmarkService {
    func takeLaunchWarning() -> String? { nil }
}
