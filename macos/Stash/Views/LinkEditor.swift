import AppKit
import SwiftUI

/// The sheet for adding a bookmark or editing one.
struct LinkEditor: View {
    enum Target: Identifiable, Hashable {
        case add(folderID: LinkFolder.ID?)
        case edit(SavedLink.ID)

        var id: Self { self }
    }

    @Environment(LinkStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: Target

    @State private var address = ""
    @State private var name = ""
    @State private var folderID: LinkFolder.ID?
    /// Comma-separated.
    @State private var tags = ""

    private var isAdding: Bool {
        if case .add = target { true } else { false }
    }

    var body: some View {
        let url = URL(webAddress: address)

        Form {
            Section {
                TextField("Address", text: $address, prompt: Text("https://example.com"))
                TextField("Name", text: $name, prompt: Text(isAdding ? "Title of the page" : url?.displayHost ?? ""))
                TextField("Tags", text: $tags, prompt: Text("react, shadcn, effects"))
                Picker("Folder", selection: $folderID) {
                    Text("None").tag(LinkFolder.ID?.none)
                    if !store.folders.isEmpty {
                        Divider()
                    }
                    ForEach(store.folders) { folder in
                        Text(folder.name).tag(Optional(folder.id))
                    }
                }
            } header: {
                Text(isAdding ? "Add Bookmark" : "Edit Bookmark")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isAdding ? "Add" : "Save") {
                    if let url { save(url) }
                }
                .disabled(url == nil)
            }
        }
        .onAppear(perform: fill)
    }

    /// Seeds the fields once, when the sheet opens.
    private func fill() {
        switch target {
        case .add(let folderID):
            self.folderID = folderID
            // Likely just copied from the browser.
            if let copied = NSPasteboard.general.string(forType: .string), URL(webAddress: copied) != nil {
                address = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case .edit(let id):
            guard let link = store.link(id: id) else { return }
            address = link.url.absoluteString
            name = link.title
            folderID = link.folderID
            tags = link.tags.joined(separator: ", ")
        }
    }

    private func save(_ url: URL) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = SavedLink.normalizedTags(tags.split(separator: ",").map(String.init))
        switch target {
        case .add:
            Task { await store.add(url, title: title.isEmpty ? nil : title, to: folderID, tags: tags) }
        case .edit(let id):
            Task { await store.edit(id, url: url, title: title, folderID: folderID, tags: tags) }
        }
        dismiss()
    }
}
