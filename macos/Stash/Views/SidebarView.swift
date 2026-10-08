import SwiftUI

struct SidebarView: View {
    @Environment(BookmarkStore.self) private var store
    @Binding var selection: SidebarItem?
    @State private var showsCollections = true
    @State private var showsAuthors = false
    @State private var renamingCollectionID: BookmarkCollection.ID?
    @State private var collectionPendingDeletion: BookmarkCollection?

    var body: some View {
        // Worked out once per update rather than once per row.
        let counts = store.sidebarCounts
        let authors = store.authors

        List(selection: $selection) {
            Section {
                row("All", systemImage: "square.grid.2x2", item: .all, counts: counts)
                row("Inbox", systemImage: "tray", item: .inbox, counts: counts)
                row("Trash", systemImage: "trash", item: .trash, counts: counts)
                    .contextMenu {
                        Button("Empty Trash", role: .destructive) {
                            Task { await store.emptyTrash() }
                        }
                        .disabled(counts[.trash, default: 0] == 0)
                    }
            }

            Section("Collections", isExpanded: $showsCollections) {
                ForEach(store.collections) { collection in
                    CollectionRow(
                        collection: collection,
                        count: counts[.collection(id: collection.id), default: 0],
                        renamingID: $renamingCollectionID
                    )
                        .tag(SidebarItem.collection(id: collection.id))
                        .contextMenu {
                            Button("Rename") {
                                renamingCollectionID = collection.id
                            }
                            Button("Delete Collection…", role: .destructive) {
                                collectionPendingDeletion = collection
                            }
                        }
                        .dropDestination(for: String.self) { bookmarkIDs, _ in
                            add(bookmarkIDs, to: collection)
                        }
                }

                Button(action: createCollection) {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            if !authors.isEmpty {
                Section("Authors", isExpanded: $showsAuthors) {
                    ForEach(authors) { summary in
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
        .confirmationDialog(
            "Delete “\(collectionPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { collectionPendingDeletion != nil },
                set: { if !$0 { collectionPendingDeletion = nil } }
            ),
            presenting: collectionPendingDeletion
        ) { collection in
            Button("Delete Collection", role: .destructive) {
                delete(collection)
            }
        } message: { _ in
            Text("Posts in this collection stay in your library.")
        }
    }

    private func row(_ title: String, systemImage: String, item: SidebarItem, counts: [SidebarItem: Int]) -> some View {
        Label(title, systemImage: systemImage)
            .badge(counts[item, default: 0])
            .tag(item)
    }

    private func createCollection() {
        showsCollections = true
        Task {
            guard let collection = await store.createCollection() else { return }
            selection = .collection(id: collection.id)
            renamingCollectionID = collection.id
        }
    }

    private func delete(_ collection: BookmarkCollection) {
        if selection == .collection(id: collection.id) {
            selection = .all
        }
        Task { await store.deleteCollection(collection.id) }
    }

    private func add(_ bookmarkIDs: [String], to collection: BookmarkCollection) -> Bool {
        let known = bookmarkIDs.filter { store.bookmark(id: $0) != nil }
        guard !known.isEmpty else { return false }
        Task {
            for id in known {
                await store.setCollection(collection.id, included: true, for: id)
            }
        }
        return true
    }
}

/// A collection in the sidebar; turns into a text field while being renamed.
private struct CollectionRow: View {
    @Environment(BookmarkStore.self) private var store
    let collection: BookmarkCollection
    let count: Int
    @Binding var renamingID: BookmarkCollection.ID?

    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        if renamingID == collection.id {
            Label {
                TextField("Collection Name", text: $draft)
                    .focused($isEditing)
                    .onSubmit(commit)
                    .onExitCommand { renamingID = nil }
            } icon: {
                Image(systemName: "rectangle.stack")
            }
            .task {
                draft = collection.name
                isEditing = true
            }
            .onChange(of: isEditing) {
                if !isEditing { commit() }
            }
        } else {
            Label(collection.name, systemImage: "rectangle.stack")
                .badge(count)
        }
    }

    private func commit() {
        guard renamingID == collection.id else { return }
        renamingID = nil

        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != collection.name else { return }
        Task { await store.renameCollection(collection.id, to: name) }
    }
}
