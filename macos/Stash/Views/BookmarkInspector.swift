import SwiftUI

struct BookmarkInspector: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(\.openURL) private var openURL

    let bookmark: Bookmark

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    AvatarView(author: bookmark.author, size: 36)
                    VStack(alignment: .leading) {
                        Text(bookmark.author.name)
                            .font(.headline)
                        Text("@\(bookmark.author.handle)")
                            .foregroundStyle(.secondary)
                    }
                }

                if !bookmark.text.isEmpty {
                    Text(bookmark.text)
                        .textSelection(.enabled)
                }

                ForEach(bookmark.media, id: \.self) { media in
                    Group {
                        switch media.kind {
                        case .photo:
                            RemoteImage(url: media.url, placeholderAspectRatio: media.aspectRatio)
                        case .video:
                            // Only the first video starts by itself, so several don't play at once.
                            InspectorVideo(media: media, autoplays: media == bookmark.media.first(where: \.isPlayable))
                        case .gif:
                            LoopingVideoView(url: media.url)
                                .aspectRatio(media.aspectRatio, contentMode: .fit)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            Section("Collections") {
                ForEach(store.collections) { collection in
                    Toggle(collection.name, isOn: store.membership(of: bookmark.id, in: collection.id))
                }
            }

            Section("Details") {
                LabeledContent("Source", value: "X")
                LabeledContent("Author", value: "@\(bookmark.author.handle)")
                LabeledContent("Posted", value: bookmark.postedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Saved", value: bookmark.savedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Link") {
                    Text(bookmark.url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Section {
                Button("Open on X", systemImage: "arrow.up.right.square") {
                    openURL(bookmark.url)
                }
            }
        }
        .formStyle(.grouped)
    }
}
