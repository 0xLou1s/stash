import SwiftUI

/// The Bookmarks detail: folders and links in columns, like Finder's list view
/// (a List rather than a Table, which can't hide the lines between rows).
/// Double-click opens; drag a link in from the browser to save it.
struct LinksView: View {
    @Environment(LinkStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Binding var mode: LibraryMode
    @Binding var scope: LinkSidebarItem?
    let searchText: String

    @State private var selection: Set<LinkListItem> = []
    /// Nil keeps the store's order: newest saved first.
    @State private var sort: LinkSort?
    @State private var editor: LinkEditor.Target?
    @State private var showsChromeImport = false

    private var currentScope: LinkSidebarItem { scope ?? .all }

    /// Dropping adds to the folder on screen; not while searching across
    /// folders, or into Trash or a tag.
    private var acceptsDrops: Bool {
        guard searchText.isEmpty else { return false }
        return switch currentScope {
        case .all, .folder: true
        case .trash, .tag: false
        }
    }

    var body: some View {
        let showsFolders = currentScope == .all && searchText.isEmpty
        let folders = showsFolders ? store.folders : []
        let links = store.links(in: currentScope, matching: searchText)
        let counts = showsFolders ? store.sidebarCounts : [:]
        // Folders stay above links, as each group sorts by the same column.
        let folderRows = sorted(folders.map { (entry: LinkListEntry(folder: $0, count: counts[.folder(id: $0.id), default: 0]), url: URL?.none) })
        let linkRows = sorted(links.map { (entry: LinkListEntry(link: $0), url: $0.url) })

        List(selection: $selection) {
            ForEach(folderRows, id: \.entry.id) { entry, _ in
                LinkListRow(entry: entry)
                    .tag(entry.id)
                    .listRowSeparator(.hidden)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard case .folder(let id) = entry.id else { return false }
                        return store.drop(urls, into: id)
                    }
            }
            ForEach(linkRows, id: \.entry.id) { entry, url in
                LinkListRow(entry: entry)
                    .tag(entry.id)
                    .listRowSeparator(.hidden)
                    .draggable(url)
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top, spacing: 0) {
            LinkColumnHeader(sort: $sort)
        }
        .contextMenu(forSelectionType: LinkListItem.self) { items in
            menu(for: items)
        } primaryAction: { items in
            open(items)
        }
        .onDeleteCommand(perform: deleteSelection)
        .pasteDestination(for: String.self) { strings in
            paste(strings)
        } validator: { strings in
            acceptsDrops ? strings.filter { !Self.webAddresses(in: [$0]).isEmpty } : []
        }
        .dropDestination(for: URL.self) { urls, _ in
            acceptsDrops && store.drop(urls, into: currentScope.folderID)
        }
        .overlay {
            if folderRows.isEmpty && linkRows.isEmpty {
                emptyState
            }
        }
        .navigationTitle(title)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup {
                LibraryModeMenu(mode: $mode)

                Button("Add Bookmark", systemImage: "plus") {
                    editor = .add(folderID: currentScope.folderID)
                }
                .keyboardShortcut("d")
                .help("Add Bookmark (⌘D)")

                Button("Import from Chrome", systemImage: "square.and.arrow.down") {
                    showsChromeImport = true
                }
                .help("Import from Chrome")

                Button(currentScope == .trash ? "Delete Immediately" : "Move to Trash", systemImage: "trash") {
                    deleteSelection()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selectedLinkIDs.isEmpty)

                AppearanceMenu()
            }
        }
        .sheet(item: $editor) { target in
            LinkEditor(target: target)
        }
        .sheet(isPresented: $showsChromeImport) {
            ChromeImportSheet(scope: $scope)
        }
        .onChange(of: scope) {
            selection = []
        }
        .errorAlert(Bindable(store).errorMessage)
    }

    /// Rows in the clicked column's order, or as given when no column is.
    /// Each entry travels with what its row drags: a link's address, or nothing for a folder.
    private func sorted<DragURL>(_ rows: [(entry: LinkListEntry, url: DragURL)]) -> [(entry: LinkListEntry, url: DragURL)] {
        guard let sort else { return rows }
        return rows.sorted { sort.areInIncreasingOrder($0.entry, $1.entry) }
    }

    // MARK: - Menus and actions

    @ViewBuilder
    private func menu(for items: Set<LinkListItem>) -> some View {
        let linkIDs = Self.linkIDs(in: items)
        if items.isEmpty {
            if acceptsDrops {
                Button("Add Bookmark…", systemImage: "plus") {
                    editor = .add(folderID: currentScope.folderID)
                }
            }
            Button("Import from Chrome…", systemImage: "square.and.arrow.down") {
                showsChromeImport = true
            }
        } else if linkIDs.isEmpty {
            if items.count == 1, case .folder(let id)? = items.first {
                Button("Open Folder", systemImage: "folder") {
                    scope = .folder(id: id)
                }
            }
        } else {
            LinkActions(ids: linkIDs) { editor = .edit($0) }
        }
    }

    /// Double-click or Return: a folder opens in place; links open in the browser.
    private func open(_ items: Set<LinkListItem>) {
        if items.count == 1, case .folder(let id)? = items.first {
            scope = .folder(id: id)
            return
        }
        for id in Self.linkIDs(in: items) {
            if let url = store.link(id: id)?.webURL { openURL(url) }
        }
    }

    private var selectedLinkIDs: Set<SavedLink.ID> {
        Self.linkIDs(in: selection)
    }

    private func deleteSelection() {
        let ids = selectedLinkIDs
        guard !ids.isEmpty else { return }
        selection.subtract(ids.map(LinkListItem.link))
        Task {
            if currentScope == .trash {
                await store.deletePermanently(ids)
            } else {
                await store.moveToTrash(ids)
            }
        }
    }

    private func paste(_ strings: [String]) {
        _ = store.drop(Self.webAddresses(in: strings), into: currentScope.folderID)
    }

    /// One copied address, or several on separate lines.
    private static func webAddresses(in strings: [String]) -> [URL] {
        strings
            .flatMap { $0.split(whereSeparator: \.isNewline) }
            .compactMap { URL(webAddress: String($0)) }
    }

    private static func linkIDs(in items: Set<LinkListItem>) -> Set<SavedLink.ID> {
        Set(items.compactMap { item in
            if case .link(let id) = item { id } else { nil }
        })
    }

    // MARK: - Empty states and title

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search
        } else {
            switch currentScope {
            case .trash:
                ContentUnavailableView("Trash Is Empty", systemImage: "trash")
            case .tag(let tag):
                ContentUnavailableView(
                    "Nothing Tagged “\(tag)”",
                    systemImage: "tag",
                    description: Text("Right-click a bookmark and choose Tags to add it.")
                )
            case .folder:
                ContentUnavailableView(
                    "No Bookmarks in This Folder",
                    systemImage: "folder",
                    description: Text("Drag a link here from your browser, or copy one and press ⌘V.")
                )
            case .all:
                ContentUnavailableView {
                    Label("No Bookmarks Yet", systemImage: "bookmark")
                } description: {
                    Text("Drag a link here from your browser, copy one and press ⌘V, or press ⌘D to add one.")
                } actions: {
                    Button("Import from Chrome…") {
                        showsChromeImport = true
                    }
                }
            }
        }
    }

    /// Used for the window name in the Window menu; the toolbar hides it.
    private var title: String {
        switch currentScope {
        case .all: "All Bookmarks"
        case .trash: "Trash"
        case .folder(let id): store.folder(id: id)?.name ?? "Folder"
        case .tag(let tag): tag
        }
    }
}
