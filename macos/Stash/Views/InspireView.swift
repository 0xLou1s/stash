import SwiftUI

/// The Inspire detail: the gallery of saved posts, with the post inspector.
struct InspireView: View {
    @Environment(BookmarkStore.self) private var store
    @Binding var mode: LibraryMode
    let scope: SidebarItem
    let searchText: String

    @State private var selection: Bookmark.ID?
    @State private var showsInspector = false

    var body: some View {
        GalleryView(
            bookmarks: store.bookmarks(in: scope, matching: searchText),
            scope: scope,
            isSearching: !searchText.isEmpty,
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
                LibraryModeMenu(mode: $mode)

                Button(scope == .trash ? "Delete Immediately" : "Move to Trash", systemImage: "trash") {
                    guard let selection else { return }
                    Task {
                        if scope == .trash {
                            await store.deletePermanently([selection])
                        } else {
                            await store.moveToTrash([selection])
                        }
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selection == nil)

                AppearanceMenu()

                Button("Inspector", systemImage: "sidebar.right") {
                    showsInspector.toggle()
                }
            }
        }
        .onChange(of: scope) {
            selection = nil
        }
        .onChange(of: selection) {
            // Selecting a post opens the panel; deselecting (clicking it again) closes it.
            showsInspector = selection != nil
        }
        .errorAlert(Bindable(store).errorMessage)
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
        switch scope {
        case .all: "All"
        case .inbox: "Inbox"
        case .trash: "Trash"
        case .collection(let id):
            store.collections.first { $0.id == id }?.name ?? "Collection"
        case .author(let handle):
            store.library.first { $0.author.handle == handle }?.author.name ?? "@\(handle)"
        }
    }
}
