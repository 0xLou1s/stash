import AppKit
import SwiftUI

/// Menu items shared by the gallery context menu and the inspector.
struct BookmarkActions: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(\.openURL) private var openURL

    let bookmark: Bookmark

    var body: some View {
        Button("Open on X", systemImage: "arrow.up.right.square") {
            if let url = bookmark.webURL { openURL(url) }
        }
        Button("Copy Link", systemImage: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bookmark.url.absoluteString, forType: .string)
        }
        ShareLink(item: bookmark.url)
        Divider()

        if bookmark.isTrashed {
            Button("Put Back", systemImage: "arrow.uturn.backward") {
                Task { await store.putBack([bookmark.id]) }
            }
            Button("Delete Immediately", systemImage: "trash.slash", role: .destructive) {
                Task { await store.deletePermanently([bookmark.id]) }
            }
        } else {
            Menu("Add to Collection", systemImage: "rectangle.stack") {
                ForEach(store.collections) { collection in
                    Toggle(collection.name, isOn: store.membership(of: bookmark.id, in: collection.id))
                }
            }
            Divider()
            Button("Move to Trash", systemImage: "trash") {
                Task { await store.moveToTrash([bookmark.id]) }
            }
        }
    }
}

extension BookmarkStore {
    /// Whether a post is in a collection, as a binding that saves on change.
    func membership(of bookmarkID: Bookmark.ID, in collectionID: BookmarkCollection.ID) -> Binding<Bool> {
        Binding(
            get: { self.bookmark(id: bookmarkID)?.collectionIDs.contains(collectionID) ?? false },
            set: { included in
                Task { await self.setCollection(collectionID, included: included, for: bookmarkID) }
            }
        )
    }
}
