import SwiftUI

struct GalleryView: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("galleryLayout") private var layoutStyle: GalleryLayoutStyle = .rows
    @AppStorage("galleryScale") private var scale = 1.0
    @AppStorage("gallerySort") private var sortOrder: GallerySortOrder = .newestSaved

    let bookmarks: [Bookmark]
    let isSearching: Bool
    let isTrash: Bool
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
                    MasonryLayout(minColumnWidth: 220 * scale, spacing: 20) {
                        ForEach(sorted) { bookmark in
                            interactive(BookmarkCard(bookmark: bookmark, isSelected: selection == bookmark.id), for: bookmark)
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
                } else if isTrash {
                    ContentUnavailableView("Trash Is Empty", systemImage: "trash")
                } else {
                    ContentUnavailableView(
                        "Nothing Here Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Save posts from X with the Stash button and they show up here.")
                    )
                }
            }
        }
    }

    private func interactive(_ content: some View, for bookmark: Bookmark) -> some View {
        content
            .onTapGesture(count: 2) { openURL(bookmark.url) }
            .onTapGesture { selection = bookmark.id }
            .contextMenu { BookmarkActions(bookmark: bookmark) }
    }
}
