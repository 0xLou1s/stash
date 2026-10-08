import SwiftUI

struct GalleryView: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("galleryLayoutStyle") private var layoutStyle: GalleryLayoutStyle = .masonry
    @AppStorage("galleryScale") private var scale = 1.0
    @AppStorage("gallerySort") private var sortOrder: GallerySortOrder = .newestSaved

    let bookmarks: [Bookmark]
    let scope: SidebarItem
    let isSearching: Bool
    @Binding var selection: Bookmark.ID?

    var body: some View {
        let sorted = bookmarks.sorted(by: sortOrder.areInIncreasingOrder)

        ScrollView {
            Group {
                switch layoutStyle {
                case .rows:
                    JustifiedLayout(rowHeight: 200 * scale, spacing: 28) {
                        ForEach(sorted) { bookmark in
                            interactive(GalleryTile(bookmark: bookmark, isSelected: selection == bookmark.id), for: bookmark)
                                .layoutAspectRatio(bookmark.coverAspectRatio)
                        }
                    }
                case .masonry:
                    // Equal-width columns; every image and video keeps its own height.
                    MasonryLayout(minColumnWidth: 220 * scale, spacing: 20) {
                        ForEach(sorted) { bookmark in
                            let tile = interactive(GalleryTile(bookmark: bookmark, isSelected: selection == bookmark.id), for: bookmark)
                            if let cover = bookmark.media.first {
                                tile.aspectRatio(cover.aspectRatio, contentMode: .fit)
                            } else {
                                tile
                            }
                        }
                    }
                }
            }
            .padding(28)
            .padding(.bottom, 60) // room to scroll past the floating controls
        }
        .overlay(alignment: .bottom) {
            GalleryControls(layoutStyle: $layoutStyle, scale: $scale, sortOrder: $sortOrder)
                .padding(.bottom, 16)
        }
        .overlay {
            if bookmarks.isEmpty && !store.isLoading {
                if isSearching {
                    ContentUnavailableView.search
                } else {
                    emptyState
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch scope {
        case .trash:
            ContentUnavailableView("Trash Is Empty", systemImage: "trash")
        case .inbox:
            ContentUnavailableView(
                "Inbox Is Empty",
                systemImage: "tray",
                description: Text("Posts that aren't in a collection show up here.")
            )
        case .collection:
            ContentUnavailableView(
                "No Posts in This Collection",
                systemImage: "rectangle.stack",
                description: Text("Drag posts onto the collection in the sidebar, or right-click a post and choose Add to Collection.")
            )
        case .all, .author:
            ContentUnavailableView(
                "Nothing Here Yet",
                systemImage: "photo.on.rectangle",
                description: Text("Save posts from X with the Stash button and they show up here.")
            )
        }
    }

    private func interactive(_ content: some View, for bookmark: Bookmark) -> some View {
        content
            .onTapGesture(count: 2) { openURL(bookmark.url) }
            .onTapGesture { selection = selection == bookmark.id ? nil : bookmark.id }
            .contextMenu { BookmarkActions(bookmark: bookmark) }
            .draggable(bookmark.id)
    }
}
