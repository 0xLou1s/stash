import Foundation
import Observation
import os

struct AuthorSummary: Identifiable {
    let author: Bookmark.Author
    let count: Int

    var id: String { author.handle }
}

@Observable
final class BookmarkStore {
    /// Everything not deleted, including posts in Trash.
    private(set) var bookmarks: [Bookmark] = []
    private(set) var collections: [BookmarkCollection] = []
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let service: any BookmarkService
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Stash", category: "BookmarkStore")

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
            collections = try await service.fetchCollections().sorted { $0.createdAt < $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
        if let warning = service.takeLaunchWarning() {
            errorMessage = warning
        }
    }

    func bookmark(id: Bookmark.ID) -> Bookmark? {
        bookmarks.first { $0.id == id }
    }

    // MARK: - From the extension

    // These report failure to the caller (the extension retries) instead of
    // through `errorMessage`, which would raise an alert on every retry.

    /// A post saved in the browser. Saving again refreshes its content and
    /// brings it back from Trash, but keeps its collections and first save date.
    @discardableResult
    func ingest(_ incoming: Bookmark) async -> Bool {
        var merged = incoming
        if let existing = bookmark(id: incoming.id) {
            merged.collectionIDs = existing.collectionIDs
            merged.savedAt = existing.savedAt
        }
        merged.trashedAt = nil
        merged.deletedAt = nil
        merged.updatedAt = .now

        do {
            try await persist(merged)
            return true
        } catch {
            logger.error("Couldn't save post \(incoming.id, privacy: .public) from the extension: \(error, privacy: .public)")
            return false
        }
    }

    /// A post removed in the browser. It goes to Trash rather than vanishing.
    @discardableResult
    func ingestRemoval(id: Bookmark.ID) async -> Bool {
        guard var trashed = bookmark(id: id), !trashed.isTrashed else { return true }
        trashed.trashedAt = .now
        trashed.updatedAt = .now
        do {
            try await persist(trashed)
            return true
        } catch {
            logger.error("Couldn't trash post \(id, privacy: .public) removed in the extension: \(error, privacy: .public)")
            return false
        }
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

    /// Creates an empty collection with a placeholder name, ready to be renamed.
    func createCollection() async -> BookmarkCollection? {
        let taken = Set(collections.map(\.name))
        var name = "New Collection"
        var suffix = 2
        while taken.contains(name) {
            name = "New Collection \(suffix)"
            suffix += 1
        }

        let collection = BookmarkCollection(name: name)
        do {
            try await service.saveCollection(collection)
            collections.append(collection)
            return collection
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renameCollection(_ id: BookmarkCollection.ID, to name: String) async {
        guard var updated = collections.first(where: { $0.id == id }) else { return }
        updated.name = name
        updated.updatedAt = .now
        do {
            try await service.saveCollection(updated)
            if let index = collections.firstIndex(where: { $0.id == id }) {
                collections[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCollection(_ id: BookmarkCollection.ID) async {
        do {
            try await service.deleteCollection(id: id)
            collections.removeAll { $0.id == id }
            for index in bookmarks.indices where bookmarks[index].collectionIDs.contains(id) {
                bookmarks[index].collectionIDs.remove(id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func update(_ id: Bookmark.ID, _ change: (inout Bookmark) -> Void) async -> Bool {
        guard var updated = bookmark(id: id) else { return false }
        change(&updated)
        updated.updatedAt = .now
        do {
            try await persist(updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Saves to disk, then mirrors the change in memory (newest saved first).
    private func persist(_ bookmark: Bookmark) async throws {
        try await service.saveBookmark(bookmark)
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index] = bookmark
        } else {
            bookmarks.append(bookmark)
        }
        bookmarks.sort { $0.savedAt > $1.savedAt }
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

    /// How many posts each sidebar item holds, in one pass over the library.
    /// Items with no posts are absent; read with `counts[item, default: 0]`.
    var sidebarCounts: [SidebarItem: Int] {
        var counts: [SidebarItem: Int] = [:]
        for bookmark in bookmarks {
            guard !bookmark.isTrashed else {
                counts[.trash, default: 0] += 1
                continue
            }
            counts[.all, default: 0] += 1
            if bookmark.collectionIDs.isEmpty {
                counts[.inbox, default: 0] += 1
            }
            for id in bookmark.collectionIDs {
                counts[.collection(id: id), default: 0] += 1
            }
        }
        return counts
    }
}
