import { storage } from "#imports"

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

// Saved posts live in chrome.storage.local for now. When the server exists,
// these functions are the only place that needs to change.
const bookmarksItem = storage.defineItem<Record<string, Bookmark>>("local:bookmarks", {
  fallback: {},
})

export async function getBookmarks(): Promise<Bookmark[]> {
  return sortNewestFirst(await bookmarksItem.getValue())
}

export function watchBookmarks(callback: (bookmarks: Bookmark[]) => void): () => void {
  return bookmarksItem.watch((all) => callback(sortNewestFirst(all)))
}

export async function saveBookmark(bookmark: NewBookmark): Promise<void> {
  const all = await bookmarksItem.getValue()
  await bookmarksItem.setValue({
    ...all,
    [bookmark.id]: { ...bookmark, savedAt: new Date().toISOString() },
  })
}

export async function removeBookmark(id: string): Promise<void> {
  const { [id]: _removed, ...rest } = await bookmarksItem.getValue()
  await bookmarksItem.setValue(rest)
}

function sortNewestFirst(all: Record<string, Bookmark>): Bookmark[] {
  return Object.values(all).sort((a, b) => b.savedAt.localeCompare(a.savedAt))
}
