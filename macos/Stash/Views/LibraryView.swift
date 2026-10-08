import SwiftUI

struct LibraryView: View {
    @Environment(BookmarkStore.self) private var store
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var selection: Bookmark.ID?
    @State private var searchText = ""
    @State private var showsInspector = false
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            GalleryView(
                bookmarks: store.bookmarks(in: sidebarSelection ?? .all, matching: searchText),
                isSearching: !searchText.isEmpty,
                isTrash: sidebarSelection == .trash,
                selection: $selection
            )
            .navigationTitle(title)
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .inspector(isPresented: $showsInspector) {
                inspector
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button(sidebarSelection == .trash ? "Delete Immediately" : "Move to Trash", systemImage: "trash") {
                        guard let selection else { return }
                        Task {
                            if sidebarSelection == .trash {
                                await store.deletePermanently([selection])
                            } else {
                                await store.moveToTrash([selection])
                            }
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(selection == nil)

                    Menu("Appearance", systemImage: "circle.lefthalf.filled") {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(Appearance.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    .help("Appearance")

                    Button("Inspector", systemImage: "sidebar.right") {
                        showsInspector.toggle()
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search posts")
        .onChange(of: sidebarSelection) {
            selection = nil
        }
        .onChange(of: selection) {
            if selection != nil { showsInspector = true }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let selection, let bookmark = store.bookmark(id: selection) {
            BookmarkInspector(bookmark: bookmark)
        } else {
            ContentUnavailableView(
                "No Post Selected",
                systemImage: "sidebar.right",
                description: Text("Select a post to see its details.")
            )
        }
    }

    /// Used for the window name in the Window menu; the toolbar hides it.
    private var title: String {
        switch sidebarSelection ?? .all {
        case .all: "All"
        case .inbox: "Inbox"
        case .trash: "Trash"
        case .collection(let id):
            store.collections.first { $0.id == id }?.name ?? "Collection"
        case .author(let handle):
            store.authors.first { $0.id == handle }?.author.name ?? "@\(handle)"
        }
    }
}

#Preview {
    @Previewable @State var store = BookmarkStore(service: MockBookmarkService())
    LibraryView()
        .environment(store)
        .task { await store.load() }
}
