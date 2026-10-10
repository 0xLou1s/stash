import SwiftUI

/// Picks Chrome bookmark folders to copy into Stash. Each ticked folder becomes
/// a Stash folder holding its pages and its subfolders' pages.
struct ChromeImportSheet: View {
    @Environment(LinkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chromeImportProfile") private var profileID = "Default"

    /// Set to the first imported folder, to show it.
    @Binding var scope: LinkSidebarItem?

    @State private var profiles: [ChromeProfile] = []
    @State private var folders: [ChromeFolder] = []
    @State private var readError: String?
    @State private var selected: Set<ChromeFolder.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from Chrome")
                .font(.headline)

            if profiles.count > 1 {
                Picker("Profile", selection: $profileID) {
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
            }

            content
                .frame(height: 340)

            Text("Each folder you tick becomes a folder in Stash, including the bookmarks in its subfolders. Bookmarks already in Stash are skipped.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import", action: importSelection)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedFolders.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            profiles = ChromeBookmarks.profiles()
            if !profiles.contains(where: { $0.id == profileID }), let first = profiles.first {
                profileID = first.id
            }
            readFolders()
        }
        .onChange(of: profileID) {
            selected = []
            readFolders()
        }
    }

    @ViewBuilder
    private var content: some View {
        if profiles.isEmpty {
            ContentUnavailableView(
                "Chrome Bookmarks Not Found",
                systemImage: "bookmark.slash",
                description: Text("Stash looks for Chrome's bookmarks in your Library folder.")
            )
        } else if let readError {
            ContentUnavailableView("Couldn't Read Bookmarks", systemImage: "exclamationmark.triangle", description: Text(readError))
        } else if folders.isEmpty {
            ContentUnavailableView("No Bookmarks in This Profile", systemImage: "bookmark")
        } else {
            List {
                ForEach(folders) { folder in
                    ChromeFolderRow(folder: folder, isInSelectedFolder: false, isExpandedInitially: true, selected: $selected)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds(.disabled)
        }
    }

    private func readFolders() {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        do {
            folders = try ChromeBookmarks.folders(in: Data(contentsOf: profile.bookmarksURL))
            readError = nil
        } catch {
            folders = []
            readError = error.localizedDescription
        }
    }

    /// Ticked folders, leaving out ones inside another ticked folder (already included).
    private var selectedFolders: [ChromeFolder] {
        func collect(_ folders: [ChromeFolder]) -> [ChromeFolder] {
            folders.flatMap { selected.contains($0.id) ? [$0] : collect($0.subfolders) }
        }
        return collect(folders)
    }

    private var summary: String {
        let folders = selectedFolders
        guard !folders.isEmpty else { return "No folders selected" }
        let pages = folders.reduce(0) { $0 + $1.pageCount }
        return "\(pages) bookmarks from \(folders.count) \(folders.count == 1 ? "folder" : "folders")"
    }

    private func importSelection() {
        let folders = selectedFolders
        dismiss()
        Task {
            var added: [SavedLink] = []
            for folder in folders {
                added += await store.importPages(folder.allPages, intoFolderNamed: folder.name)
            }
            if let first = folders.first, let stashFolder = store.folders.first(where: { $0.name == first.name }) {
                scope = .folder(id: stashFolder.id)
            }
            await store.loadIcons(for: added.map(\.id))
        }
    }
}

/// A folder with a checkbox; subfolders of a ticked folder show as included.
private struct ChromeFolderRow: View {
    let folder: ChromeFolder
    let isInSelectedFolder: Bool
    @Binding var selected: Set<ChromeFolder.ID>

    @State private var isExpanded: Bool

    init(folder: ChromeFolder, isInSelectedFolder: Bool, isExpandedInitially: Bool = false, selected: Binding<Set<ChromeFolder.ID>>) {
        self.folder = folder
        self.isInSelectedFolder = isInSelectedFolder
        _selected = selected
        // Only a starting point; the person expands and collapses from there.
        _isExpanded = State(initialValue: isExpandedInitially)
    }

    var body: some View {
        if folder.subfolders.isEmpty {
            checkbox
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(folder.subfolders) { subfolder in
                    ChromeFolderRow(
                        folder: subfolder,
                        isInSelectedFolder: isInSelectedFolder || selected.contains(folder.id),
                        selected: $selected
                    )
                }
            } label: {
                checkbox
            }
        }
    }

    private var checkbox: some View {
        Toggle(isOn: Binding(
            get: { isInSelectedFolder || selected.contains(folder.id) },
            set: { isOn in
                if isOn { selected.insert(folder.id) } else { selected.remove(folder.id) }
            }
        )) {
            HStack {
                Label(folder.name, systemImage: "folder")
                    .lineLimit(1)
                Spacer()
                Text(folder.pageCount, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isInSelectedFolder)
    }
}
