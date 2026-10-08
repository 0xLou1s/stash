import { browser, storage } from "#imports"

// Same shape the Mac app decodes (see README "Bookmark shape").

export type MediaKind = "photo" | "video" | "gif"

export interface Media {
  kind: MediaKind
  /** The image for photos; the mp4 for videos and GIFs. */
  url: string
  /** Still frame for videos and GIFs. */
  posterURL: string | null
  width: number | null
  height: number | null
}

export interface Author {
  name: string
  handle: string
  avatarURL: string | null
}

export interface Bookmark {
  id: string
  url: string
  author: Author
  text: string
  media: Media[]
  postedAt: string
  savedAt: string
}

export type NewBookmark = Omit<Bookmark, "savedAt">

/** What still has to reach the library (the Mac app now, the cloud later), by post id. */
export type PendingChange = "upsert" | "delete"

// Saved posts live in chrome.storage.local, which survives browser restarts
// and extension updates. Every change is also queued in `pendingItem` until
// the background script delivers it (see sync.ts).
//
// Each change rewrites a whole map, so two writers could overwrite each
// other's changes. Only the background script writes: the content script and
// popup ask it to (`requestSave`, `requestRemove`), and it runs each change
// to completion before the next (`oneAtATime`).
const bookmarksItem = storage.defineItem<Record<string, Bookmark>>("local:bookmarks", {
  fallback: {},
})

const pendingItem = storage.defineItem<Record<string, PendingChange>>("local:pendingSync", {
  fallback: {},
})

export async function getBookmarks(): Promise<Bookmark[]> {
  return sortNewestFirst(await bookmarksItem.getValue())
}

export async function getBookmark(id: string): Promise<Bookmark | undefined> {
  return (await bookmarksItem.getValue())[id]
}

export function watchBookmarks(callback: (bookmarks: Bookmark[]) => void): () => void {
  return bookmarksItem.watch((all) => callback(sortNewestFirst(all)))
}

// MARK: - Writes (background script only)

let lastWrite: Promise<unknown> = Promise.resolve()

function oneAtATime<T>(change: () => Promise<T>): Promise<T> {
  const run = lastWrite.then(change, change)
  lastWrite = run.catch(() => {})
  return run
}

export function saveBookmark(bookmark: NewBookmark): Promise<void> {
  return oneAtATime(async () => {
    const all = await bookmarksItem.getValue()
    await bookmarksItem.setValue({
      ...all,
      [bookmark.id]: { ...bookmark, savedAt: new Date().toISOString() },
    })
    await queueChange(bookmark.id, "upsert")
  })
}

export function removeBookmark(id: string): Promise<void> {
  return oneAtATime(async () => {
    const { [id]: _removed, ...rest } = await bookmarksItem.getValue()
    await bookmarksItem.setValue(rest)
    await queueChange(id, "delete")
  })
}

// MARK: - Asking the background script to write

export type LibraryMessage =
  | { type: "save"; bookmark: NewBookmark }
  | { type: "remove"; id: string }
  | { type: "sync" }

export type LibraryReply = { ok: true } | { ok: false; error: string }

export function requestSave(bookmark: NewBookmark): Promise<void> {
  return send({ type: "save", bookmark })
}

export function requestRemove(id: string): Promise<void> {
  return send({ type: "remove", id })
}

async function send(message: LibraryMessage): Promise<void> {
  const reply = (await browser.runtime.sendMessage(message)) as LibraryReply | undefined
  if (!reply?.ok) throw new Error(reply?.error ?? "The extension's background script didn't answer")
}

// MARK: - Sync queue (also background script only)

export async function getPendingChanges(): Promise<Record<string, PendingChange>> {
  return pendingItem.getValue()
}

export function watchPendingChanges(callback: (pending: Record<string, PendingChange>) => void): () => void {
  return pendingItem.watch(callback)
}

/** Clears a delivered change, unless a newer one for the same post was queued meanwhile. */
export function markDelivered(id: string, change: PendingChange): Promise<void> {
  return oneAtATime(async () => {
    const pending = await pendingItem.getValue()
    if (pending[id] !== change) return
    const { [id]: _delivered, ...rest } = pending
    await pendingItem.setValue(rest)
  })
}

/** Queues every saved post, e.g. for posts saved before sync existed. */
export function queueAllForSync(): Promise<void> {
  return oneAtATime(async () => {
    const ids = Object.keys(await bookmarksItem.getValue())
    const pending = await pendingItem.getValue()
    await pendingItem.setValue({
      ...Object.fromEntries(ids.map((id) => [id, "upsert" as const])),
      ...pending,
    })
  })
}

async function queueChange(id: string, change: PendingChange): Promise<void> {
  const pending = await pendingItem.getValue()
  await pendingItem.setValue({ ...pending, [id]: change })
}

function sortNewestFirst(all: Record<string, Bookmark>): Bookmark[] {
  return Object.values(all).sort((a, b) => b.savedAt.localeCompare(a.savedAt))
}
