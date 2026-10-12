import AppKit
import SwiftUI

/// Context menu items for one or more selected links.
struct LinkActions: View {
    @Environment(LinkStore.self) private var store
    @Environment(\.openURL) private var openURL

    let ids: Set<SavedLink.ID>
    let edit: (SavedLink.ID) -> Void

    var body: some View {
        let links = store.links.filter { ids.contains($0.id) }

        Button(links.count == 1 ? "Open" : "Open \(links.count) Bookmarks", systemImage: "arrow.up.right.square") {
            for link in links {
                if let url = link.webURL { openURL(url) }
            }
        }
        Button(links.count == 1 ? "Copy Link" : "Copy Links", systemImage: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(links.map(\.url.absoluteString).joined(separator: "\n"), forType: .string)
        }
        if links.count == 1, let link = links.first {
            ShareLink(item: link.url)
        }
        Divider()

        if links.allSatisfy(\.isTrashed) {
            Button("Put Back", systemImage: "arrow.uturn.backward") {
                Task { await store.putBack(ids) }
            }
            Button("Delete Immediately", systemImage: "trash.slash", role: .destructive) {
                Task { await store.deletePermanently(ids) }
            }
        } else {
            if links.count == 1, let link = links.first {
                Button("Edit…", systemImage: "pencil") {
                    edit(link.id)
                }
            }
            Menu("Tags", systemImage: "tag") {
                ForEach(store.tags, id: \.self) { tag in
                    Toggle(tag, isOn: Binding(
                        get: { links.allSatisfy { $0.tags.contains(tag) } },
                        set: { included in Task { await store.setTag(tag, included: included, for: ids) } }
                    ))
                }
                if links.count == 1, let link = links.first {
                    if !store.tags.isEmpty {
                        Divider()
                    }
                    Button("New Tag…") {
                        edit(link.id)
                    }
                }
            }
            Menu("Move to Folder", systemImage: "folder") {
                Button("None") {
                    Task { await store.move(ids, to: nil) }
                }
                if !store.folders.isEmpty {
                    Divider()
                }
                ForEach(store.folders) { folder in
                    Button(folder.name) {
                        Task { await store.move(ids, to: folder.id) }
                    }
                }
            }
            Divider()
            Button("Move to Trash", systemImage: "trash") {
                Task { await store.moveToTrash(ids) }
            }
        }
    }
}

extension LinkStore {
    /// Saves pages dropped or pasted into a folder (nil for none), moving ones
    /// already saved. Returns false when none of them is a web page.
    func drop(_ urls: [URL], into folderID: LinkFolder.ID?) -> Bool {
        let pages = urls.filter(\.isWebPage)
        guard !pages.isEmpty else { return false }
        Task { await add(pages, to: folderID) }
        return true
    }
}
