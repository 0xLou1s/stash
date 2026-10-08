# Stash

A private visual library for X posts: save from Chrome, browse in a native macOS app.

```
stash/
├── macos/       SwiftUI app (Xcode project, macOS 15+)
├── extension/   Chrome extension (WXT + React + shadcn/ui)
└── server/      (next) API both sides talk to
```

## macOS app

Open `macos/Stash.xcodeproj` in Xcode and press Run.

The library is a JSON file at
`~/Library/Application Support/com.example.stash/library.json` (the folder is the app's bundle id).
It lives outside the app, so it survives updates and reinstalls. Writes are atomic.
A file the app can't read is moved aside (`library-unreadable-*.json`), never overwritten,
and a file from a newer app version opens read-only.

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
- `src/lib/bookmarks.ts` reads and writes saved posts in `chrome.storage.local`
  and queues every change for sync.
- `src/lib/sync.ts` (run by `src/entrypoints/background.ts`) delivers the queue.

Stash only stores posts you save with its button. It doesn't sign in to X or import X bookmarks.

## Sync

Each side keeps its own local copy; nothing needs a server yet.

```
X page ──save──▶ extension storage ──queue──▶ Mac app (127.0.0.1:47811) ──▶ library.json
```

- The extension saves locally first, then queues the change (`upsert` or `delete`).
  The background script delivers the queue whenever the Mac app is running: right away,
  when the popup opens, and every minute otherwise. Nothing is lost while the app is closed.
- The app's endpoint (`ExtensionBridge.swift`) listens on 127.0.0.1 only and refuses
  requests from web pages. Removing a post in the browser moves it to the app's Trash.
- Changes made in the app (collections, Trash) stay in the app. Sync is one way for now.

**Moving to the cloud.** The local routes match the planned API
(`PUT /v1/bookmarks/{id}`, `DELETE /v1/bookmarks/{id}`), so the extension switches by
changing `APP_URL` in `sync.ts` and adding auth. On the Mac, every record carries
`updatedAt` and a `deletedAt` marker for deletions, which is what a sync engine needs
to merge both ways. It runs next to `LocalBookmarkService`; the views don't change.

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
  "trashedAt": null,
  "updatedAt": "2026-10-08T14:00:00.000Z",
  "deletedAt": null
}
```

`kind` is `photo`, `video` or `gif`. For videos and GIFs, `url` is the mp4 and `posterURL` the still frame.
`width`/`height` can be `null` if X didn't provide them and the image hadn't loaded yet.
`collectionIDs`, `trashedAt`, `updatedAt` and `deletedAt` are set by the Mac app; the extension doesn't send them.
