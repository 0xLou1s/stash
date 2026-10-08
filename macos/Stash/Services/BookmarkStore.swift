import Foundation
import Observation

struct AuthorSummary: Identifiable {
    let author: Bookmark.Author
    let count: Int

    var id: String { author.handle }
}

@Observable
final class BookmarkStore {
    /// Everything, including posts in Trash.
    private(set) var bookmarks: [Bookmark] = []
    private(set) var collections: [BookmarkCollection] = []
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let service: any BookmarkService

    init(service: any BookmarkService) {
        self.service = service
    }

    /// Posts not in Trash.
    var library: [Bookmark] {
        bookmarks.filter { !$0.isTrashed }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            bookmarks = try await service.fetchBookmarks().sorted { $0.savedAt > $1.savedAt }
            collections = try await service.fetchCollections()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bookmark(id: Bookmark.ID) -> Bookmark? {
        bookmarks.first { $0.id == id }
    }

    // MARK: - Changes

    func moveToTrash(_ ids: Set<Bookmark.ID>) async {
        for id in ids {
            await update(id) { $0.trashedAt = .now }
        }
    }

    func putBack(_ ids: Set<Bookmark.ID>) async {
        for id in ids {
            await update(id) { $0.trashedAt = nil }
        }
    }

    func deletePermanently(_ ids: Set<Bookmark.ID>) async {
        do {
            for id in ids {
                try await service.deleteBookmark(id: id)
            }
            bookmarks.removeAll { ids.contains($0.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func emptyTrash() async {
        await deletePermanently(Set(bookmarks.filter(\.isTrashed).map(\.id)))
    }

    func setCollection(_ collectionID: BookmarkCollection.ID, included: Bool, for bookmarkID: Bookmark.ID) async {
        await update(bookmarkID) {
            if included {
                $0.collectionIDs.insert(collectionID)
            } else {
                $0.collectionIDs.remove(collectionID)
            }
        }
    }

    private func update(_ id: Bookmark.ID, _ change: (inout Bookmark) -> Void) async {
        guard var updated = bookmark(id: id) else { return }
        change(&updated)
        do {
            try await service.updateBookmark(updated)
            if let index = bookmarks.firstIndex(where: { $0.id == id }) {
                bookmarks[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Queries

    /// Authors ordered by how many of their posts are saved.
    var authors: [AuthorSummary] {
        Dictionary(grouping: library, by: \.author.handle)
            .compactMap { _, posts in
                posts.first.map { AuthorSummary(author: $0.author, count: posts.count) }
            }
            .sorted { ($0.count, $1.author.name) > ($1.count, $0.author.name) }
    }

    func bookmarks(in item: SidebarItem, matching query: String) -> [Bookmark] {
        let scoped: [Bookmark] = switch item {
        case .all:
            library
        case .inbox:
            library.filter { $0.collectionIDs.isEmpty }
        case .trash:
            bookmarks.filter(\.isTrashed)
        case .collection(let id):
            library.filter { $0.collectionIDs.contains(id) }
        case .author(let handle):
            library.filter { $0.author.handle == handle }
        }

        guard !query.isEmpty else { return scoped }
        return scoped.filter {
            $0.text.localizedStandardContains(query)
                || $0.author.name.localizedStandardContains(query)
                || $0.author.handle.localizedStandardContains(query)
        }
    }

    func count(in item: SidebarItem) -> Int {
        bookmarks(in: item, matching: "").count
    }
}
