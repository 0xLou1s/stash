import SwiftUI

struct SidebarView: View {
    @Environment(BookmarkStore.self) private var store
    @Binding var selection: SidebarItem?
    @State private var showsCollections = true
    @State private var showsAuthors = false

    var body: some View {
        List(selection: $selection) {
            Section {
                row("All", systemImage: "square.grid.2x2", item: .all)
                row("Inbox", systemImage: "tray", item: .inbox)
                row("Trash", systemImage: "trash", item: .trash)
                    .contextMenu {
                        Button("Empty Trash", role: .destructive) {
                            Task { await store.emptyTrash() }
                        }
                        .disabled(store.count(in: .trash) == 0)
                    }
            }

            Section("Collections", isExpanded: $showsCollections) {
                ForEach(store.collections) { collection in
                    row(collection.name, systemImage: "rectangle.stack", item: .collection(id: collection.id))
                }
            }

            if !store.authors.isEmpty {
                Section("Authors", isExpanded: $showsAuthors) {
                    ForEach(store.authors) { summary in
                        Label {
                            Text(summary.author.name)
                        } icon: {
                            AvatarView(author: summary.author, size: 18)
                        }
                        .badge(summary.count)
                        .tag(SidebarItem.author(handle: summary.author.handle))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ title: String, systemImage: String, item: SidebarItem) -> some View {
        Label(title, systemImage: systemImage)
            .badge(store.count(in: item))
            .tag(item)
    }
}
