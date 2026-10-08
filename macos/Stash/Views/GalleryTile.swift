import SwiftUI

/// A post in the gallery. Fills whatever frame the layout gives it: the cover
/// image or video cropped to fit, or the text for text-only posts.
struct GalleryTile: View {
    let bookmark: Bookmark
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        Group {
            if let cover = bookmark.media.first {
                ZStack {
                    if let still = cover.stillURL {
                        RemoteImage(url: still, contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                    }

                    // Play videos and GIFs while the pointer is over them.
                    if cover.isPlayable && isHovered {
                        LoopingVideoView(url: cover.url)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            } else {
                textTile
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) {
            if let cover = bookmark.media.first, cover.isPlayable, !isHovered {
                PlayableBadge(kind: cover.kind)
            }
        }
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
                .lineLimit(8)
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
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

private struct PlayableBadge: View {
    let kind: Bookmark.Media.Kind

    var body: some View {
        Group {
            if kind == .gif {
                Text("GIF")
                    .font(.caption2.weight(.bold))
            } else {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .accessibilityLabel("Video")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(8)
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
