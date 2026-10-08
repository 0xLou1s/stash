import Foundation

/// A saved X post. Field names match the JSON the Chrome extension sends.
struct Bookmark: Identifiable, Hashable, Codable {
    struct Author: Hashable, Codable {
        var name: String
        var handle: String
        var avatarURL: URL?
    }

    struct Media: Hashable, Codable {
        var url: URL
        var width: Double?
        var height: Double?

        var aspectRatio: CGFloat {
            guard let width, let height, width > 0, height > 0 else { return 4 / 3 }
            return width / height
        }
    }

    /// The X post id, e.g. "1843021234567890123".
    let id: String
    var url: URL
    var author: Author
    var text: String
    var media: [Media]
    var postedAt: Date
    var savedAt: Date
    var collectionIDs: Set<BookmarkCollection.ID>
    /// Set when the post is moved to Trash; nil while it's in the library.
    var trashedAt: Date?

    var isTrashed: Bool { trashedAt != nil }

    /// Width / height of the post's gallery tile. Text-only posts are square.
    var coverAspectRatio: CGFloat {
        media.first?.aspectRatio ?? 1
    }
}
