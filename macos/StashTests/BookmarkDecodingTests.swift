import Foundation
import Testing
@testable import Stash

@Suite("Decoding bookmarks")
struct BookmarkDecodingTests {
    /// Exactly what the Chrome extension sends: no app-only fields, JS dates with milliseconds.
    let extensionJSON = """
    {
      "id": "1843",
      "url": "https://x.com/maya/status/1843",
      "author": { "name": "Maya", "handle": "maya", "avatarURL": null },
      "text": "hello",
      "media": [
        { "kind": "video", "url": "https://video.twimg.com/v.mp4", "posterURL": "https://pbs.twimg.com/v.jpg", "width": 720, "height": 1280 },
        { "kind": "photo", "url": "https://pbs.twimg.com/p.jpg", "posterURL": null, "width": null, "height": null }
      ],
      "postedAt": "2026-10-08T12:00:00.000Z",
      "savedAt": "2026-10-08T14:00:00.123Z"
    }
    """

    @Test func `reads what the extension sends`() throws {
        let bookmark = try StashJSON.decoder.decode(Bookmark.self, from: Data(extensionJSON.utf8))

        #expect(bookmark.id == "1843")
        #expect(bookmark.author.avatarURL == nil)
        #expect(bookmark.media.map(\.kind) == [.video, .photo])
        // 2026-10-08T14:00:00.123Z, milliseconds kept
        #expect(abs(bookmark.savedAt.timeIntervalSince1970 - 1791468000.123) < 0.0005)
    }

    @Test func `defaults the fields only the app sets`() throws {
        let bookmark = try StashJSON.decoder.decode(Bookmark.self, from: Data(extensionJSON.utf8))

        #expect(bookmark.collectionIDs.isEmpty)
        #expect(bookmark.trashedAt == nil)
        #expect(bookmark.deletedAt == nil)
        #expect(bookmark.updatedAt == bookmark.savedAt)
    }

    @Test func `round-trips through the library format`() throws {
        var original = Bookmark.sample(id: "7", text: "kept", collectionIDs: ["design"])
        original.deletedAt = Date(timeIntervalSince1970: 1_800_000_500.25)

        let data = try StashJSON.encoder.encode(original)
        let decoded = try StashJSON.decoder.decode(Bookmark.self, from: data)

        #expect(decoded == original)
    }

    @Test func `uses a still for videos and the image itself for photos`() throws {
        let bookmark = try StashJSON.decoder.decode(Bookmark.self, from: Data(extensionJSON.utf8))
        let video = try #require(bookmark.media.first)
        let photo = try #require(bookmark.media.last)

        #expect(video.stillURL?.absoluteString == "https://pbs.twimg.com/v.jpg")
        #expect(abs(video.aspectRatio - 720 / 1280) < 1e-9)
        #expect(photo.stillURL == photo.url)
        #expect(abs(photo.aspectRatio - 4 / 3) < 1e-9, "no size known: falls back to 4:3")
    }

    @Test func `rejects dates that aren't ISO 8601`() {
        let json = extensionJSON.replacingOccurrences(of: "2026-10-08T12:00:00.000Z", with: "yesterday")

        #expect(throws: DecodingError.self) {
            try StashJSON.decoder.decode(Bookmark.self, from: Data(json.utf8))
        }
    }

    @Test func `trusts only links that point at X`() throws {
        var bookmark = try StashJSON.decoder.decode(Bookmark.self, from: Data(extensionJSON.utf8))
        #expect(bookmark.hasTrustedLinks)
        #expect(bookmark.webURL == bookmark.url)

        bookmark.url = URL(string: "file:///Applications/Calculator.app")!
        #expect(!bookmark.hasTrustedLinks)
        #expect(bookmark.webURL == nil, "never handed to the system to open")
    }
}
