import SwiftUI

/// A post in the Masonry layout: full image plus a few lines of text.
struct BookmarkCard: View {
    let bookmark: Bookmark
    let isSelected: Bool

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    private var hasMedia: Bool { !bookmark.media.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover = bookmark.media.first {
                RemoteImage(url: cover.url, placeholderAspectRatio: cover.aspectRatio)
                    .overlay(alignment: .topTrailing) {
                        if bookmark.media.count > 1 {
                            MediaCountBadge(count: bookmark.media.count)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 12) {
                if !bookmark.text.isEmpty {
                    Text(bookmark.text)
                        .font(hasMedia ? .callout : .body)
                        .foregroundStyle(hasMedia ? .secondary : .primary)
                        .lineLimit(hasMedia ? 3 : 10)
                        .lineSpacing(hasMedia ? 0 : 3)
                }
                AuthorLine(author: bookmark.author)
            }
            .padding(hasMedia ? 14 : 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                lineWidth: isSelected ? 2 : 1
            )
        }
        .contentShape(shape)
    }
}
