import Foundation

/// Everything in the library, as written to disk.
struct LibrarySnapshot: Codable {
    /// Bump when the file format changes in a way older versions can't read,
    /// and migrate in `LocalBookmarkService.load`.
    ///
    /// 2 added `links` and `linkFolders`. Version 1 apps could read the file
    /// but would drop both on their next write, so they must open it read-only.
    static let currentSchemaVersion = 2

    var schemaVersion = currentSchemaVersion
    /// Includes deleted records (`deletedAt` set) so deletions can sync later.
    var bookmarks: [Bookmark] = []
    var collections: [BookmarkCollection] = []
    var links: [SavedLink] = []
    var linkFolders: [LinkFolder] = []
}

extension LibrarySnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        bookmarks = try container.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
        collections = try container.decodeIfPresent([BookmarkCollection].self, forKey: .collections) ?? []
        links = try container.decodeIfPresent([SavedLink].self, forKey: .links) ?? []
        linkFolders = try container.decodeIfPresent([LinkFolder].self, forKey: .linkFolders) ?? []
    }
}

/// Just the format version, readable even when the rest of the file isn't.
private struct FormatVersion: Decodable {
    var schemaVersion: Int?
}

enum LibraryError: LocalizedError {
    case unreadable(backupURL: URL?, underlying: Error)
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable(let backupURL, let underlying):
            if let backupURL {
                "Your library couldn't be read, so a new one was started. The old file was kept at \(backupURL.path(percentEncoded: false)). (\(underlying.localizedDescription))"
            } else {
                "Your library couldn't be read: \(underlying.localizedDescription)"
            }
        case .newerVersion(let version):
            "This library was saved by a newer version of Stash (format \(version)). Update Stash to make changes."
        }
    }
}

/// The library as a JSON file in Application Support:
/// `~/Library/Application Support/<bundle id>/library.json`.
///
/// That folder lives outside the app bundle, so the library survives app
/// updates and reinstalls. Every write replaces the file atomically, so a
/// crash mid-write leaves the previous version intact.
final class LocalBookmarkService: BookmarkService {
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Stash", directoryHint: .isDirectory)
            .appending(path: "library.json")
    }

    private let fileURL: URL
    private var snapshot: LibrarySnapshot
    /// Set when the file on disk can't be safely written (see `LibraryError`).
    private var writeBlocker: LibraryError?
    /// Reported once, through `takeLaunchWarning()`.
    private var pendingWarning: LibraryError?

    init(fileURL: URL = LocalBookmarkService.defaultFileURL) {
        self.fileURL = fileURL
        snapshot = LibrarySnapshot()
        load()
    }

    // MARK: - BookmarkService

    func fetchBookmarks() async throws -> [Bookmark] {
        snapshot.bookmarks.filter { $0.deletedAt == nil }
    }

    func saveBookmark(_ bookmark: Bookmark) async throws {
        try write { snapshot in
            if let index = snapshot.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                snapshot.bookmarks[index] = bookmark
            } else {
                snapshot.bookmarks.append(bookmark)
            }
        }
    }

    func deleteBookmark(id: Bookmark.ID) async throws {
        try write { snapshot in
            guard let index = snapshot.bookmarks.firstIndex(where: { $0.id == id }) else { return }
            snapshot.bookmarks[index].deletedAt = .now
            snapshot.bookmarks[index].updatedAt = .now
        }
    }

    func fetchCollections() async throws -> [BookmarkCollection] {
        snapshot.collections.filter { $0.deletedAt == nil }
    }

    func saveCollection(_ collection: BookmarkCollection) async throws {
        try write { snapshot in
            if let index = snapshot.collections.firstIndex(where: { $0.id == collection.id }) {
                snapshot.collections[index] = collection
            } else {
                snapshot.collections.append(collection)
            }
        }
    }

    func deleteCollection(id: BookmarkCollection.ID) async throws {
        try write { snapshot in
            guard let index = snapshot.collections.firstIndex(where: { $0.id == id }) else { return }
            snapshot.collections[index].deletedAt = .now
            snapshot.collections[index].updatedAt = .now
            for bookmarkIndex in snapshot.bookmarks.indices where snapshot.bookmarks[bookmarkIndex].collectionIDs.contains(id) {
                snapshot.bookmarks[bookmarkIndex].collectionIDs.remove(id)
                snapshot.bookmarks[bookmarkIndex].updatedAt = .now
            }
        }
    }

    func fetchLinks() async throws -> [SavedLink] {
        snapshot.links.filter { $0.deletedAt == nil }
    }

    func saveLink(_ link: SavedLink) async throws {
        try write { $0.links.upsert(link) }
    }

    func saveLinks(_ links: [SavedLink]) async throws {
        try write { snapshot in
            for link in links {
                snapshot.links.upsert(link)
            }
        }
    }

    func deleteLink(id: SavedLink.ID) async throws {
        try write { snapshot in
            guard let index = snapshot.links.firstIndex(where: { $0.id == id }) else { return }
            snapshot.links[index].deletedAt = .now
            snapshot.links[index].updatedAt = .now
        }
    }

    func fetchLinkFolders() async throws -> [LinkFolder] {
        snapshot.linkFolders.filter { $0.deletedAt == nil }
    }

    func saveLinkFolder(_ folder: LinkFolder) async throws {
        try write { $0.linkFolders.upsert(folder) }
    }

    func deleteLinkFolder(id: LinkFolder.ID) async throws {
        try write { snapshot in
            guard let index = snapshot.linkFolders.firstIndex(where: { $0.id == id }) else { return }
            snapshot.linkFolders[index].deletedAt = .now
            snapshot.linkFolders[index].updatedAt = .now
            for linkIndex in snapshot.links.indices where snapshot.links[linkIndex].folderID == id {
                snapshot.links[linkIndex].folderID = nil
                snapshot.links[linkIndex].updatedAt = .now
            }
        }
    }

    // MARK: - File

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return // First launch: start with an empty library.
        }

        do {
            let data = try Data(contentsOf: fileURL)

            // Check the format version on its own first: a newer version's file
            // may not decode here at all, and must not be mistaken for a broken one.
            let version = (try? StashJSON.decoder.decode(FormatVersion.self, from: data))?.schemaVersion ?? 1
            if version > LibrarySnapshot.currentSchemaVersion {
                // Writing would drop whatever the newer version added. Read only,
                // showing whatever this version can make sense of.
                writeBlocker = .newerVersion(version)
                pendingWarning = writeBlocker
                snapshot = (try? StashJSON.decoder.decode(LibrarySnapshot.self, from: data)) ?? LibrarySnapshot()
                return
            }

            snapshot = try StashJSON.decoder.decode(LibrarySnapshot.self, from: data)
        } catch {
            // Never overwrite a library we couldn't read. Move it aside and start fresh.
            let backupURL = fileURL.deletingLastPathComponent()
                .appending(path: "library-unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: fileURL, to: backupURL)
                pendingWarning = .unreadable(backupURL: backupURL, underlying: error)
            } catch {
                writeBlocker = .unreadable(backupURL: nil, underlying: error)
                pendingWarning = writeBlocker
            }
        }
    }

    /// Applies `change` to a copy, writes it, and only then keeps it, so memory
    /// and disk never disagree after a failed write.
    private func write(_ change: (inout LibrarySnapshot) -> Void) throws {
        if let writeBlocker { throw writeBlocker }

        var updated = snapshot
        change(&updated)
        // A file from an older version is now in this version's format; say so,
        // or that version would open it and drop what it doesn't know about.
        updated.schemaVersion = LibrarySnapshot.currentSchemaVersion

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try StashJSON.encoder.encode(updated).write(to: fileURL, options: .atomic)
        snapshot = updated
    }

    func takeLaunchWarning() -> String? {
        defer { pendingWarning = nil }
        return pendingWarning?.localizedDescription
    }
}

private extension Array where Element: Identifiable {
    /// Replaces the element with the same id, or appends.
    mutating func upsert(_ element: Element) {
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        } else {
            append(element)
        }
    }
}
