import Foundation

/// A row in the bookmarks list, as selected.
enum LinkListItem: Hashable {
    case folder(LinkFolder.ID)
    case link(SavedLink.ID)
}

/// The columns of the bookmarks list, which sort when their header is clicked.
enum LinkColumn: CaseIterable {
    case name, tags, site

    var title: String {
        switch self {
        case .name: "Name"
        case .tags: "Tags"
        case .site: "Site"
        }
    }
}

struct LinkSort: Equatable {
    var column: LinkColumn
    var ascending = true

    func areInIncreasingOrder(_ lhs: LinkListEntry, _ rhs: LinkListEntry) -> Bool {
        let order = lhs.sortKey(for: column).localizedStandardCompare(rhs.sortKey(for: column))
        return ascending ? order == .orderedAscending : order == .orderedDescending
    }
}

/// What one row shows: a folder or a link, flattened so both fit the same
/// columns and sort by them.
struct LinkListEntry: Identifiable {
    let id: LinkListItem
    let name: String
    let iconURL: URL?
    let tags: [String]
    /// The link's domain; empty for folders.
    let site: String
    /// What the Tags column sorts by.
    let tagsText: String
    let help: String
    /// For folders: how many links they hold.
    let count: Int?

    var isFolder: Bool { count != nil }

    func sortKey(for column: LinkColumn) -> String {
        switch column {
        case .name: name
        case .tags: tagsText
        case .site: site
        }
    }

    init(link: SavedLink) {
        id = .link(link.id)
        name = link.title
        iconURL = link.iconURL
        tags = link.tags
        site = link.url.displayHost
        tagsText = link.tags.joined(separator: ", ")
        help = ([link.title, link.url.absoluteString] + (link.tags.isEmpty ? [] : [tagsText])).joined(separator: "\n")
        count = nil
    }

    init(folder: LinkFolder, count: Int) {
        id = .folder(folder.id)
        name = folder.name
        iconURL = nil
        tags = []
        site = ""
        tagsText = ""
        help = folder.name
        self.count = count
    }
}
