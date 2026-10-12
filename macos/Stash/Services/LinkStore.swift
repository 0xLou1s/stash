import Foundation
import Observation

/// Saved web pages and their folders: the Bookmarks half of the library.
@Observable
final class LinkStore {
    /// Everything not deleted, including links in Trash. Newest saved first.
    private(set) var links: [SavedLink] = []
    private(set) var folders: [LinkFolder] = []
    var errorMessage: String?

    @ObservationIgnored private let service: any BookmarkService
    @ObservationIgnored private let loadMetadata: @Sendable (URL) async -> LinkMetadata?

    init(service: any BookmarkService, loadMetadata: @escaping @Sendable (URL) async -> LinkMetadata? = { await LinkMetadataFetcher.fetch($0) }) {
        self.service = service
        self.loadMetadata = loadMetadata
    }

    func load() async {
        do {
            links = try await service.fetchLinks().sorted { $0.savedAt > $1.savedAt }
            folders = try await service.fetchLinkFolders().sorted { $0.createdAt < $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func link(id: SavedLink.ID) -> SavedLink? {
        links.first { $0.id == id }
    }

    func folder(id: LinkFolder.ID) -> LinkFolder? {
        folders.first { $0.id == id }
    }

    // MARK: - Adding

    /// Saves a page, then fills in its title and icon from the web. A page
    /// that's already saved isn't duplicated: it moves to `folderID` and comes
    /// back from Trash, gaining `tags`. Without a `title`, the page's own is used.
    @discardableResult
    func add(_ url: URL, title: String? = nil, to folderID: LinkFolder.ID? = nil, tags: [String] = []) async -> SavedLink? {
        let (link, isNew) = prepare(url, title: title, folderID: folderID, tags: tags)
        guard await save([link]) else { return nil }
        if isNew {
            await refreshMetadata(of: [link.id], keepingTitles: title != nil)
        }
        return self.link(id: link.id)
    }

    /// Adds every page to the folder; ones already saved move there. All are
    /// saved at once, then their titles and icons load together.
    func add(_ urls: [URL], to folderID: LinkFolder.ID?) async {
        var seen = Set<URL>()
        let prepared = urls
            .filter { seen.insert($0).inserted }
            .map { prepare($0, title: nil, folderID: folderID, tags: []) }
        guard await save(prepared.map(\.link)) else { return }
        await refreshMetadata(of: prepared.filter(\.isNew).map(\.link.id), keepingTitles: false)
    }

    /// The saved link for `url` with the changes applied, or a new one.
    private func prepare(_ url: URL, title: String?, folderID: LinkFolder.ID?, tags: [String]) -> (link: SavedLink, isNew: Bool) {
        if var existing = links.first(where: { $0.url == url }) {
            existing.folderID = folderID
            existing.trashedAt = nil
            existing.tags = SavedLink.normalizedTags(existing.tags + tags)
            if let title { existing.title = title }
            return (existing, false)
        }
        var link = SavedLink(url: url, title: title, folderID: folderID)
        link.tags = SavedLink.normalizedTags(tags)
        return (link, true)
    }

    // MARK: - Page details

    /// Fills in titles (unless `keepingTitles`, or the link was renamed) and
    /// icons from the web, a few pages at a time. Each shows as it arrives;
    /// they're saved in batches, as they are at that moment, so a rename,
    /// move, or delete made while loading is never undone.
    func refreshMetadata(of ids: [SavedLink.ID], keepingTitles: Bool) async {
        var pending = ids
            .compactMap { link(id: $0) }
            .map { ($0.id, $0.url) }
            .makeIterator()
        let loadMetadata = self.loadMetadata
        var unsaved: Set<SavedLink.ID> = []

        await withTaskGroup(of: (SavedLink.ID, URL, LinkMetadata?).self) { group in
            for _ in 0..<6 {
                guard let (id, url) = pending.next() else { break }
                group.addTask { (id, url, await loadMetadata(url)) }
            }
            for await (id, url, metadata) in group {
                if let (id, url) = pending.next() {
                    group.addTask { (id, url, await loadMetadata(url)) }
                }
                // Re-check: the link may have been edited or deleted while loading.
                guard let metadata, let index = links.firstIndex(where: { $0.id == id }), links[index].url == url else { continue }
                var link = links[index]
                if !keepingTitles, link.title == url.displayHost, let title = metadata.title {
                    link.title = title
                }
                link.iconURL = metadata.iconURL ?? link.iconURL
                guard link != links[index] else { continue }
                link.updatedAt = .now
                links[index] = link
                unsaved.insert(id)
                if unsaved.count >= 25 {
                    await saveCurrentState(of: unsaved)
                    unsaved.removeAll()
                }
            }
        }
        await saveCurrentState(of: unsaved)
    }

    /// Writes links as they are now, skipping any deleted since.
    private func saveCurrentState(of ids: Set<SavedLink.ID>) async {
        let current = links.filter { ids.contains($0.id) }
        guard !current.isEmpty else { return }
        do {
            try await service.saveLinks(current)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Importing

    /// Adds pages from another browser to the folder named `folderName`, made
    /// if there isn't one and something is added. Pages already saved stay
    /// where they are. Returns the links added, which have no icons yet; see
    /// `refreshMetadata(of:keepingTitles:)`.
    @discardableResult
    func importPages(_ pages: [ImportedPage], intoFolderNamed folderName: String) async -> [SavedLink] {
        let existingFolder = folders.first { $0.name == folderName }
        let folder = existingFolder ?? LinkFolder(name: folderName)

        var known = Set(links.map(\.url))
        let added: [SavedLink] = pages.compactMap { page in
            guard page.url.isWebPage, known.insert(page.url).inserted else { return nil }
            let title = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return SavedLink(url: page.url, title: title.isEmpty ? nil : title, folderID: folder.id, savedAt: page.addedAt ?? .now)
        }
        guard !added.isEmpty else { return [] }

        if existingFolder == nil {
            do {
                try await service.saveLinkFolder(folder)
                folders.append(folder)
            } catch {
                errorMessage = error.localizedDescription
                return []
            }
        }
        return await save(added) ? added : []
    }

    // MARK: - Changes

    /// Applies an edit from the editor. A new address loads a new icon.
    func edit(_ id: SavedLink.ID, url: URL, title: String, folderID: LinkFolder.ID?, tags: [String]? = nil) async {
        guard var link = link(id: id) else { return }
        let addressChanged = link.url != url
        link.url = url
        link.title = title.isEmpty ? url.displayHost : title
        link.folderID = folderID
        if let tags { link.tags = SavedLink.normalizedTags(tags) }
        if addressChanged { link.iconURL = nil }
        guard await save([link]), addressChanged else { return }
        await refreshMetadata(of: [id], keepingTitles: !title.isEmpty)
    }

    func move(_ ids: Set<SavedLink.ID>, to folderID: LinkFolder.ID?) async {
        await update(ids) { $0.folderID = folderID }
    }

    /// Adds or removes a tag on each link.
    func setTag(_ tag: String, included: Bool, for ids: Set<SavedLink.ID>) async {
        await update(ids) { link in
            link.tags = SavedLink.normalizedTags(included ? link.tags + [tag] : link.tags.filter { $0 != tag })
        }
    }

    /// Removes a tag from every link that has it.
    func removeTag(_ tag: String) async {
        await setTag(tag, included: false, for: Set(links.filter { $0.tags.contains(tag) }.map(\.id)))
    }

    func moveToTrash(_ ids: Set<SavedLink.ID>) async {
        await update(ids) { $0.trashedAt = .now }
    }

    func putBack(_ ids: Set<SavedLink.ID>) async {
        await update(ids) { $0.trashedAt = nil }
    }

    func deletePermanently(_ ids: Set<SavedLink.ID>) async {
        do {
            try await service.deleteLinks(ids: ids)
            links.removeAll { ids.contains($0.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func emptyTrash() async {
        await deletePermanently(Set(links.filter(\.isTrashed).map(\.id)))
    }

    /// Applies `change` to each link, saving them all in one write.
    private func update(_ ids: Set<SavedLink.ID>, _ change: (inout SavedLink) -> Void) async {
        let changed = links
            .filter { ids.contains($0.id) }
            .map { link in
                var link = link
                change(&link)
                return link
            }
        await save(changed)
    }

    /// Saves to disk in one write, then mirrors the changes in memory (newest saved first).
    @discardableResult
    private func save(_ changed: [SavedLink]) async -> Bool {
        guard !changed.isEmpty else { return true }
        let now = Date.now
        let stamped = changed.map { link in
            var link = link
            link.updatedAt = now
            return link
        }
        do {
            try await service.saveLinks(stamped)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        var positions = Dictionary(uniqueKeysWithValues: links.enumerated().map { ($1.id, $0) })
        for link in stamped {
            if let index = positions[link.id] {
                links[index] = link
            } else {
                positions[link.id] = links.count
                links.append(link)
            }
        }
        links.sort { $0.savedAt > $1.savedAt }
        return true
    }

    // MARK: - Folders

    /// Creates an empty folder with a placeholder name, ready to be renamed.
    func createFolder() async -> LinkFolder? {
        let taken = Set(folders.map(\.name))
        var name = "New Folder"
        var suffix = 2
        while taken.contains(name) {
            name = "New Folder \(suffix)"
            suffix += 1
        }

        let folder = LinkFolder(name: name)
        do {
            try await service.saveLinkFolder(folder)
            folders.append(folder)
            return folder
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renameFolder(_ id: LinkFolder.ID, to name: String) async {
        guard var updated = folder(id: id) else { return }
        updated.name = name
        updated.updatedAt = .now
        do {
            try await service.saveLinkFolder(updated)
            if let index = folders.firstIndex(where: { $0.id == id }) {
                folders[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes the folder; its links stay, outside any folder.
    func deleteFolder(_ id: LinkFolder.ID) async {
        do {
            try await service.deleteLinkFolder(id: id)
            folders.removeAll { $0.id == id }
            for index in links.indices where links[index].folderID == id {
                links[index].folderID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Queries

    /// Links not in Trash.
    var library: [SavedLink] {
        links.filter { !$0.isTrashed }
    }

    /// The links to list for a sidebar item. `.all` lists the links outside any
    /// folder (the folders are listed above them), except while searching,
    /// which looks through every folder.
    func links(in item: LinkSidebarItem, matching query: String) -> [SavedLink] {
        let folderIDs = Set(folders.map(\.id))
        let scoped: [SavedLink] = switch item {
        case .all where query.isEmpty:
            // A link whose folder is gone counts as outside any folder.
            library.filter { link in link.folderID.map { !folderIDs.contains($0) } ?? true }
        case .all:
            library
        case .trash:
            links.filter(\.isTrashed)
        case .folder(let id):
            library.filter { $0.folderID == id }
        case .tag(let tag):
            library.filter { $0.tags.contains(tag) }
        }

        guard !query.isEmpty else { return scoped }
        return scoped.filter {
            $0.title.localizedStandardContains(query)
                || $0.url.absoluteString.localizedStandardContains(query)
                || $0.tags.contains { $0.localizedStandardContains(query) }
        }
    }

    /// Every tag on a link outside Trash, alphabetically.
    var tags: [String] {
        Set(library.flatMap(\.tags)).sorted()
    }

    /// How many links each sidebar item holds, in one pass.
    /// Items with no links are absent; read with `counts[item, default: 0]`.
    var sidebarCounts: [LinkSidebarItem: Int] {
        var counts: [LinkSidebarItem: Int] = [:]
        for link in links {
            guard !link.isTrashed else {
                counts[.trash, default: 0] += 1
                continue
            }
            counts[.all, default: 0] += 1
            if let folderID = link.folderID {
                counts[.folder(id: folderID), default: 0] += 1
            }
            for tag in link.tags {
                counts[.tag(tag), default: 0] += 1
            }
        }
        return counts
    }
}
