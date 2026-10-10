import SwiftUI

/// The sidebar in Bookmarks mode: everything, Trash, and folders.
struct LinkSidebarView: View {
    @Environment(LinkStore.self) private var store
    @Binding var selection: LinkSidebarItem?
    @State private var showsFolders = true
    @State private var showsTags = true
    @State private var renamingFolderID: LinkFolder.ID?
    @State private var folderPendingDeletion: LinkFolder?

    var body: some View {
        let counts = store.sidebarCounts
        let tags = store.tags

        List(selection: $selection) {
            Section {
                Label("All Bookmarks", systemImage: "bookmark")
                    .badge(counts[.all, default: 0])
                    .tag(LinkSidebarItem.all)
                    .dropDestination(for: URL.self) { urls, _ in
                        store.drop(urls, into: nil)
                    }
                Label("Trash", systemImage: "trash")
                    .badge(counts[.trash, default: 0])
                    .tag(LinkSidebarItem.trash)
                    .contextMenu {
                        Button("Empty Trash", role: .destructive) {
                            Task { await store.emptyTrash() }
                        }
                        .disabled(counts[.trash, default: 0] == 0)
                    }
            }

            Section("Folders", isExpanded: $showsFolders) {
                ForEach(store.folders) { folder in
                    RenamableRow(
                        name: folder.name,
                        systemImage: "folder",
                        count: counts[.folder(id: folder.id), default: 0],
                        isRenaming: isRenaming(folder.id)
                    ) { name in
                        Task { await store.renameFolder(folder.id, to: name) }
                    }
                    .tag(LinkSidebarItem.folder(id: folder.id))
                    .contextMenu {
                        Button("Rename") {
                            renamingFolderID = folder.id
                        }
                        Button("Delete Folder…", role: .destructive) {
                            folderPendingDeletion = folder
                        }
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        store.drop(urls, into: folder.id)
                    }
                }

                Button(action: createFolder) {
                    Label("New Folder", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            if !tags.isEmpty {
                Section("Tags", isExpanded: $showsTags) {
                    ForEach(tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .badge(counts[.tag(tag), default: 0])
                            .tag(LinkSidebarItem.tag(tag))
                            .contextMenu {
                                Button("Remove Tag from All Bookmarks", role: .destructive) {
                                    if selection == .tag(tag) { selection = .all }
                                    Task { await store.removeTag(tag) }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .confirmationDialog(
            "Delete “\(folderPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            presenting: folderPendingDeletion
        ) { folder in
            Button("Delete Folder", role: .destructive) {
                delete(folder)
            }
        } message: { _ in
            Text("Bookmarks in this folder stay in your library.")
        }
    }

    private func isRenaming(_ id: LinkFolder.ID) -> Binding<Bool> {
        Binding(
            get: { renamingFolderID == id },
            set: { if !$0, renamingFolderID == id { renamingFolderID = nil } }
        )
    }

    private func createFolder() {
        showsFolders = true
        Task {
            guard let folder = await store.createFolder() else { return }
            selection = .folder(id: folder.id)
            renamingFolderID = folder.id
        }
    }

    private func delete(_ folder: LinkFolder) {
        if selection == .folder(id: folder.id) {
            selection = .all
        }
        Task { await store.deleteFolder(folder.id) }
    }
}
