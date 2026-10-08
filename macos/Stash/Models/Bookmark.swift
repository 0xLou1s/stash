import Foundation

/// A saved X post. Field names match the JSON the Chrome extension sends.
struct Bookmark: Identifiable, Hashable, Codable {
    struct Author: Hashable, Codable {
        var name: String
        var handle: String
        var avatarURL: URL?
    }

    struct Media: Hashable, Codable {
        enum Kind: String, Codable {
            case photo, video, gif
        }

        var kind: Kind
        /// The image for photos; the mp4 for videos and GIFs.
        var url: URL
        /// Still frame for videos and GIFs.
        var posterURL: URL?
        var width: Double?
        var height: Double?

        var isPlayable: Bool { kind != .photo }

        /// The still image to show when not playing.
        var stillURL: URL? { isPlayable ? posterURL : url }

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
    /// When this record last changed. A sync engine compares this to decide which copy wins.
    var updatedAt: Date
    /// Set when the post is deleted for good. The record stays (hidden) so the
    /// deletion can reach other devices once sync exists.
    var deletedAt: Date?

    var isTrashed: Bool { trashedAt != nil }

    /// Width / height of the post's gallery tile. Text-only posts are square.
    var coverAspectRatio: CGFloat {
        media.first?.aspectRatio ?? 1
    }
}

extension Bookmark {
    /// Reads both library files from older app versions and the extension's JSON,
    /// which don't have the app-only fields. Any field added later must be
    /// optional or defaulted here, or existing libraries stop loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        author = try container.decode(Author.self, forKey: .author)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        media = try container.decodeIfPresent([Media].self, forKey: .media) ?? []
        postedAt = try container.decode(Date.self, forKey: .postedAt)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        collectionIDs = try container.decodeIfPresent(Set<BookmarkCollection.ID>.self, forKey: .collectionIDs) ?? []
        trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? savedAt
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}
