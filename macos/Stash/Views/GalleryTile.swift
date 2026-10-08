import SwiftUI

/// A post in the Rows layout: the cover image cropped to the tile, or the text for text-only posts.
struct GalleryTile: View {
    let bookmark: Bookmark
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        Group {
            if let cover = bookmark.media.first {
                RemoteImage(url: cover.url, contentMode: .fill)
            } else {
                textTile
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if bookmark.media.count > 1 {
                MediaCountBadge(count: bookmark.media.count)
            }
        }
        .overlay(alignment: .bottom) {
            if isHovered && !bookmark.media.isEmpty {
                hoverCaption
            }
        }
        .overlay {
            if isSelected {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var textTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bookmark.text)
                .font(.callout)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            AuthorLine(author: bookmark.author)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay { Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5) }
    }

    private var hoverCaption: some View {
        HStack(spacing: 6) {
            AvatarView(author: bookmark.author, size: 16)
            Text(bookmark.author.name)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
        .transition(.opacity)
    }
}

struct MediaCountBadge: View {
    let count: Int

    var body: some View {
        Label("\(count)", systemImage: "square.on.square")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
    }
}
