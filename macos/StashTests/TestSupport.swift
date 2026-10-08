import Foundation
@testable import Stash

extension Bookmark {
    static func sample(
        id: String,
        text: String = "",
        media: [Media] = [],
        savedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        collectionIDs: Set<BookmarkCollection.ID> = [],
        trashedAt: Date? = nil
    ) -> Bookmark {
        Bookmark(
            id: id,
            url: URL(string: "https://x.com/t/status/\(id)")!,
            author: Author(name: "Test", handle: "test", avatarURL: nil),
            text: text,
            media: media,
            postedAt: savedAt,
            savedAt: savedAt,
            collectionIDs: collectionIDs,
            trashedAt: trashedAt,
            updatedAt: savedAt
        )
    }
}

/// A library file in its own temporary folder, removed when the test ends.
final class TemporaryLibrary {
    let folder = URL.temporaryDirectory.appending(path: "StashTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    var fileURL: URL { folder.appending(path: "library.json") }

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func service() -> LocalBookmarkService {
        LocalBookmarkService(fileURL: fileURL)
    }

    func write(_ json: String) throws {
        try Data(json.utf8).write(to: fileURL)
    }

    func filesInFolder() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
    }
}
