import SwiftUI

struct LibraryView: View {
    @SceneStorage("libraryMode") private var mode: LibraryMode = .inspire
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var linkSidebarSelection: LinkSidebarItem? = .all
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            Group {
                switch mode {
                case .inspire:
                    SidebarView(selection: $sidebarSelection)
                case .bookmarks:
                    LinkSidebarView(selection: $linkSidebarSelection)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch mode {
            case .inspire:
                InspireView(mode: $mode, scope: sidebarSelection ?? .all, searchText: searchText)
            case .bookmarks:
                LinksView(mode: $mode, scope: $linkSidebarSelection, searchText: searchText)
            }
        }
        .searchable(text: $searchText, prompt: mode == .inspire ? "Search posts" : "Search bookmarks")
        .focusedSceneValue(\.libraryMode, $mode)
        .onChange(of: mode) {
            searchText = ""
        }
    }
}

/// Switches between Inspire and Bookmarks; in both modes' toolbars, beside
/// `AppearanceMenu`. The icon shows the current mode.
struct LibraryModeMenu: View {
    @Binding var mode: LibraryMode

    var body: some View {
        Menu(mode.title, systemImage: mode.systemImage) {
            Picker("Library", selection: $mode) {
                ForEach(LibraryMode.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .help("\(mode.title) — switch with ⌘1 and ⌘2")
    }
}

/// Light, dark, or follow the system; in both modes' toolbars.
struct AppearanceMenu: View {
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
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
    }
}

#Preview {
    @Previewable @State var store = BookmarkStore(service: LocalBookmarkService.preview)
    @Previewable @State var linkStore = LinkStore(service: LocalBookmarkService.preview)
    LibraryView()
        .environment(store)
        .environment(linkStore)
        .task {
            await store.load()
            await linkStore.load()
        }
}

#if DEBUG
extension LocalBookmarkService {
    /// One file for both previewed stores, so neither overwrites the other's changes.
    static let preview = LocalBookmarkService(fileURL: .temporaryDirectory.appending(path: "stash-preview.json"))
}
#endif
