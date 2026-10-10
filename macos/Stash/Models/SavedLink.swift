import Foundation

/// A saved web page: a site, a library, an article to come back to.
struct SavedLink: Identifiable, Hashable, Codable {
    let id: String
    var url: URL
    var title: String
    /// The page's favicon, found when the link was saved. Nil shows a globe.
    var iconURL: URL?
    /// Nil while the link isn't in a folder.
    var folderID: LinkFolder.ID?
    /// Lowercased, sorted, no repeats; see `SavedLink.normalizedTags`.
    var tags: [String] = []
    var savedAt: Date
    /// Set when the link is moved to Trash; nil while it's in the library.
    var trashedAt: Date?
    /// When this record last changed. A sync engine compares this to decide which copy wins.
    var updatedAt: Date
    /// Set when the link is deleted for good. Kept (hidden) so the deletion can sync.
    var deletedAt: Date?

    init(id: String = UUID().uuidString, url: URL, title: String? = nil, folderID: LinkFolder.ID? = nil, savedAt: Date = .now) {
        self.id = id
        self.url = url
        self.title = title ?? url.displayHost
        self.folderID = folderID
        self.savedAt = savedAt
        self.updatedAt = savedAt
    }

    var isTrashed: Bool { trashedAt != nil }

    /// Tags as stored: trimmed, lowercased, sorted, without blanks or repeats.
    static func normalizedTags(_ tags: some Sequence<String>) -> [String] {
        Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// The page's address, if it's safe to hand to the system to open.
    var webURL: URL? {
        url.isWebPage ? url : nil
    }
}

extension SavedLink {
    /// Tolerates files from older app versions; see `Bookmark.init(from:)`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? url.displayHost
        iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)
        folderID = try container.decodeIfPresent(LinkFolder.ID.self, forKey: .folderID)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .now
        trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? savedAt
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

struct LinkFolder: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var createdAt: Date
    /// When this record last changed. A sync engine compares this to decide which copy wins.
    var updatedAt: Date
    /// Set when the folder is deleted. Kept (hidden) so the deletion can sync.
    var deletedAt: Date?

    init(id: String = UUID().uuidString, name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension LinkFolder {
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

// MARK: - Web addresses

extension URL {
    /// Reads an address as typed or pasted: "ui.aceternity.com" becomes
    /// "https://ui.aceternity.com". Nil unless it's an http(s) page with a host.
    init?(webAddress text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.isWebPage else { return nil }
        self = url
    }

    /// http or https, with a host that looks like one ("localhost" or containing a dot).
    var isWebPage: Bool {
        guard ["http", "https"].contains(scheme?.lowercased()), let host = host(), !host.isEmpty else { return false }
        return host == "localhost" || host.contains(".")
    }

    /// "www.example.com" → "example.com"; the whole address if there's no host.
    var displayHost: String {
        guard let host = host(), !host.isEmpty else { return absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
