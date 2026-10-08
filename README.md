# Stash

A private visual library for X posts: save from Chrome, browse in a native macOS app.

```
stash/
├── macos/       SwiftUI app (Xcode project, macOS 15+)
├── extension/   Chrome extension (WXT + React + shadcn/ui)
└── server/      (next) API both sides talk to
```

## macOS app

Open `macos/Stash.xcodeproj` in Xcode and press Run. It currently reads mock data
from `Services/MockData.swift` through `MockBookmarkService`.

## Chrome extension

Built with [WXT](https://wxt.dev) (Vite), React, Tailwind and shadcn/ui.

```sh
cd extension
pnpm install
pnpm dev      # opens Chrome with the extension loaded, reloads on save
pnpm build    # production build in dist/chrome-mv3
```

To load a build by hand: `chrome://extensions` → Developer mode → **Load unpacked** →
pick `extension/dist/chrome-mv3`.

- `src/entrypoints/x.content/` adds the Stash button next to X's bookmark button.
- `src/entrypoints/x-media.content.ts` runs in the page and reads media details
  (real video files, original image sizes) from the responses X's app already loads.
  It makes no requests of its own.
- `src/entrypoints/popup/` is the toolbar popup: search, open and remove saved posts.
- `src/lib/bookmarks.ts` is the only place that reads and writes saved posts
  (`chrome.storage.local` for now; this is where server sync goes).

Stash only stores posts you save with its button. It doesn't sign in to X or import X bookmarks.

## Bookmark shape

Both sides use the same JSON, so the server only has to store and return it:

```json
{
  "id": "1843000000000000001",
  "url": "https://x.com/handle/status/1843000000000000001",
  "author": { "name": "Maya Chen", "handle": "mayabuilds", "avatarURL": "https://…" },
  "text": "…",
  "media": [
    { "kind": "photo", "url": "https://pbs.twimg.com/media/…", "posterURL": null, "width": 1200, "height": 675 },
    { "kind": "video", "url": "https://video.twimg.com/….mp4", "posterURL": "https://pbs.twimg.com/…", "width": 720, "height": 1280 }
  ],
  "postedAt": "2026-10-08T12:00:00.000Z",
  "savedAt": "2026-10-08T14:00:00.000Z",
  "collectionIDs": [],
  "trashedAt": null
}
```

`kind` is `photo`, `video` or `gif`. For videos and GIFs, `url` is the mp4 and `posterURL` the still frame.
`width`/`height` can be `null` if X didn't provide them and the image hadn't loaded yet.
`collectionIDs` and `trashedAt` are set from the Mac app; the extension doesn't send them.
