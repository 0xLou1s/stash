# Stash

A private visual library for X posts: save from Chrome, browse in a native macOS app.

```
stash/
├── macos/       SwiftUI app (Xcode project, macOS 15+)
├── extension/   Chrome extension (Manifest V3, no build step)
└── server/      (next) API both sides talk to
```

## macOS app

Open `macos/Stash.xcodeproj` in Xcode and press Run. It currently reads mock data
from `Services/MockData.swift` through `MockBookmarkService`.

## Chrome extension

1. Go to `chrome://extensions` and turn on Developer mode.
2. Click **Load unpacked** and pick the `extension/` folder.
3. Open x.com. Each post gets a Stash button right after the bookmark button.

Saved posts live in `chrome.storage.local` for now. To inspect them, open the
extension's service worker console and run `chrome.storage.local.get("bookmarks")`.

## Bookmark shape

Both sides use the same JSON, so the server only has to store and return it:

```json
{
  "id": "1843000000000000001",
  "url": "https://x.com/handle/status/1843000000000000001",
  "author": { "name": "Maya Chen", "handle": "mayabuilds", "avatarURL": "https://…" },
  "text": "…",
  "media": [{ "url": "https://pbs.twimg.com/media/…", "width": 1200, "height": 675 }],
  "postedAt": "2026-10-08T12:00:00.000Z",
  "savedAt": "2026-10-08T14:00:00.000Z",
  "collectionIDs": [],
  "trashedAt": null
}
```

`media` width/height can be `null` if the image hadn't loaded when the post was saved.
`collectionIDs` and `trashedAt` are set from the Mac app; the extension doesn't send them.
