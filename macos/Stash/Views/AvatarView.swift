import SwiftUI

struct AvatarView: View {
    let author: Bookmark.Author
    var size: CGFloat = 36

    var body: some View {
        AsyncImage(url: author.avatarURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Circle()
                .fill(.tint.opacity(0.2))
                .overlay {
                    Text(author.name.prefix(1).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.tint)
                }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Small avatar + name + handle, used in card and tile footers.
struct AuthorLine: View {
    let author: Bookmark.Author

    var body: some View {
        HStack(spacing: 6) {
            AvatarView(author: author, size: 16)
            Text(author.name)
                .lineLimit(1)
            Text("@\(author.handle)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
    }
}
