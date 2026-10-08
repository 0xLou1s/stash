import Foundation

struct BookmarkCollection: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var createdAt: Date
    /// When this record last changed. A sync engine compares this to decide which copy wins.
    var updatedAt: Date
    /// Set when the collection is deleted. Kept (hidden) so the deletion can sync.
    var deletedAt: Date?

    init(id: String = UUID().uuidString, name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension BookmarkCollection {
    /// Tolerates files from older app versions; see `Bookmark.init(from:)`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}
