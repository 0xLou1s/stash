import Foundation

/// A page from another browser's bookmarks.
struct ImportedPage: Hashable {
    var title: String
    var url: URL
    var addedAt: Date?
}

/// A Chrome profile that has bookmarks.
struct ChromeProfile: Identifiable, Hashable {
    /// The profile's folder, e.g. "Default" or "Profile 2".
    let id: String
    /// The name shown in Chrome's profile menu.
    let name: String
    let bookmarksURL: URL
}

/// A Chrome bookmark folder, with only the parts Stash can import: web pages,
/// and subfolders that contain some.
struct ChromeFolder: Identifiable, Hashable {
    let id: String
    let name: String
    /// Pages directly in this folder.
    let pages: [ImportedPage]
    let subfolders: [ChromeFolder]
    /// Pages here and in every subfolder.
    let pageCount: Int

    var allPages: [ImportedPage] {
        pages + subfolders.flatMap(\.allPages)
    }
}

/// Reads Chrome's bookmarks. Each profile keeps them in a JSON file that Chrome
/// replaces whole on every change, so it's safe to read while Chrome runs.
enum ChromeBookmarks {
    static let directory = URL.homeDirectory
        .appending(path: "Library/Application Support/Google/Chrome", directoryHint: .isDirectory)

    /// Profiles with a bookmarks file, by name.
    static func profiles(in directory: URL = directory) -> [ChromeProfile] {
        let localState = try? JSONDecoder().decode(LocalState.self, from: Data(contentsOf: directory.appending(path: "Local State")))
        let names = localState?.profile?.infoCache ?? [:]
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []

        return folders
            .compactMap { folder in
                let bookmarksURL = directory.appending(path: folder).appending(path: "Bookmarks")
                guard FileManager.default.fileExists(atPath: bookmarksURL.path(percentEncoded: false)) else { return nil }
                return ChromeProfile(id: folder, name: names[folder]?.name ?? folder, bookmarksURL: bookmarksURL)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The bookmarks bar, Other bookmarks, and Mobile bookmarks, leaving out any without pages.
    static func folders(in data: Data) throws -> [ChromeFolder] {
        let roots = try JSONDecoder().decode(File.self, from: data).roots
        return [roots.bookmarkBar, roots.other, roots.synced]
            .compactMap { $0.map(folder(from:)) }
            .filter { $0.pageCount > 0 }
    }

    private static func folder(from node: Node) -> ChromeFolder {
        var pages: [ImportedPage] = []
        var subfolders: [ChromeFolder] = []
        for child in node.children ?? [] {
            if child.type == "folder" {
                let subfolder = folder(from: child)
                if subfolder.pageCount > 0 { subfolders.append(subfolder) }
            } else if let address = child.url, let url = URL(string: address), url.isWebPage {
                // Skips bookmarklets (javascript:) and browser pages (chrome://).
                pages.append(ImportedPage(title: child.name ?? "", url: url, addedAt: date(fromChromeTime: child.dateAdded)))
            }
        }
        return ChromeFolder(
            id: node.id ?? UUID().uuidString,
            name: node.name ?? "Folder",
            pages: pages,
            subfolders: subfolders,
            pageCount: pages.count + subfolders.reduce(0) { $0 + $1.pageCount }
        )
    }

    /// Chrome stores times as microseconds since 1601.
    private static func date(fromChromeTime value: String?) -> Date? {
        guard let microseconds = value.flatMap(Double.init), microseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: microseconds / 1_000_000 - 11_644_473_600)
    }

    // MARK: - File formats

    private struct File: Decodable {
        struct Roots: Decodable {
            var bookmarkBar: Node?
            var other: Node?
            var synced: Node?

            enum CodingKeys: String, CodingKey {
                case bookmarkBar = "bookmark_bar", other, synced
            }
        }

        var roots: Roots
    }

    private struct Node: Decodable {
        var id: String?
        var type: String
        var name: String?
        var url: String?
        var dateAdded: String?
        var children: [Node]?

        enum CodingKeys: String, CodingKey {
            case id, type, name, url, children
            case dateAdded = "date_added"
        }
    }

    private struct LocalState: Decodable {
        struct Profile: Decodable {
            struct Info: Decodable {
                var name: String?
            }

            var infoCache: [String: Info]?

            enum CodingKeys: String, CodingKey {
                case infoCache = "info_cache"
            }
        }

        var profile: Profile?
    }
}
