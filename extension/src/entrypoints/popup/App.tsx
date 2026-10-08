import { Archive, Play, Search, Trash2 } from "lucide-react"
import { useEffect, useMemo, useState } from "react"

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { useBookmarks } from "@/hooks/use-bookmarks"
import { useSyncStatus } from "@/hooks/use-sync-status"
import { removeBookmark, type Bookmark, type Media } from "@/lib/bookmarks"
import { timeAgo } from "@/lib/format"

export default function App() {
  const bookmarks = useBookmarks()
  const [query, setQuery] = useState("")

  // Try delivering anything queued as soon as the popup opens.
  useEffect(() => {
    void browser.runtime.sendMessage({ type: "sync" }).catch(() => {})
  }, [])

  const results = useMemo(() => {
    const needle = query.trim().toLowerCase()
    if (!bookmarks || !needle) return bookmarks
    return bookmarks.filter((bookmark) =>
      [bookmark.text, bookmark.author.name, bookmark.author.handle].some((field) =>
        field.toLowerCase().includes(needle),
      ),
    )
  }, [bookmarks, query])

  const count = bookmarks?.length ?? 0

  return (
    <TooltipProvider delayDuration={400}>
      <div className="flex h-135 w-95 flex-col">
        <header className="flex items-center gap-3 px-4 pt-4 pb-3">
          <div className="grid size-8 place-items-center rounded-lg bg-primary text-primary-foreground">
            <Archive className="size-4" aria-hidden />
          </div>
          <div className="min-w-0 flex-1">
            <h1 className="text-sm leading-5 font-semibold">Stash</h1>
            <p className="text-xs text-muted-foreground">
              {count === 1 ? "1 saved post" : `${count} saved posts`}
            </p>
          </div>
        </header>

        {count > 0 && (
          <div className="px-4 pb-3">
            <div className="relative">
              <Search
                className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground"
                aria-hidden
              />
              <Input
                type="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search saved posts"
                aria-label="Search saved posts"
                className="pl-8"
              />
            </div>
          </div>
        )}

        <div className="min-h-0 flex-1 border-t">
          {bookmarks === null ? null : count === 0 ? (
            <EmptyLibrary />
          ) : results?.length === 0 ? (
            <p className="px-4 py-10 text-center text-sm text-muted-foreground">
              No saved posts match “{query.trim()}”.
            </p>
          ) : (
            <ScrollArea className="h-full">
              <ul className="divide-y">
                {results?.map((bookmark) => (
                  <BookmarkRow key={bookmark.id} bookmark={bookmark} />
                ))}
              </ul>
            </ScrollArea>
          )}
        </div>

        <SyncFooter />
      </div>
    </TooltipProvider>
  )
}

function BookmarkRow({ bookmark }: { bookmark: Bookmark }) {
  const { author, media } = bookmark

  return (
    <li className="group relative">
      <a
        href={bookmark.url}
        target="_blank"
        rel="noreferrer"
        className="flex gap-3 px-4 py-3 outline-none hover:bg-accent/60 focus-visible:bg-accent/60"
      >
        <Avatar className="size-8 shrink-0">
          <AvatarImage src={author.avatarURL ?? undefined} alt="" />
          <AvatarFallback className="text-xs">{author.name.slice(0, 1).toUpperCase()}</AvatarFallback>
        </Avatar>

        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-1 text-sm leading-5">
            <span className="truncate font-medium">{author.name}</span>
            <span className="truncate text-muted-foreground">@{author.handle}</span>
            <span className="text-muted-foreground" aria-hidden>
              ·
            </span>
            <time className="shrink-0 text-muted-foreground" dateTime={bookmark.savedAt}>
              {timeAgo(bookmark.savedAt)}
            </time>
          </div>
          {bookmark.text && <p className="mt-0.5 line-clamp-2 text-sm text-muted-foreground">{bookmark.text}</p>}
        </div>

        {media[0] && <MediaThumbnail media={media[0]} count={media.length} />}
      </a>

      <Tooltip>
        <TooltipTrigger asChild>
          <Button
            variant="secondary"
            size="icon"
            className="absolute top-2.5 right-3 size-7 opacity-0 shadow-sm group-hover:opacity-100 focus-visible:opacity-100"
            onClick={() => void removeBookmark(bookmark.id)}
            aria-label="Remove from Stash"
          >
            <Trash2 />
          </Button>
        </TooltipTrigger>
        <TooltipContent>Remove from Stash</TooltipContent>
      </Tooltip>
    </li>
  )
}

function MediaThumbnail({ media, count }: { media: Media; count: number }) {
  const still = media.kind === "photo" ? media.url : media.posterURL

  return (
    <div className="relative size-12 shrink-0 overflow-hidden rounded-md bg-muted">
      {still && <img src={still} alt="" loading="lazy" className="size-full object-cover" />}
      {media.kind !== "photo" && (
        <span className="absolute inset-0 grid place-items-center bg-black/20">
          <Play className="size-4 fill-white text-white" aria-label={media.kind === "gif" ? "GIF" : "Video"} />
        </span>
      )}
      {count > 1 && (
        <span className="absolute right-0.5 bottom-0.5 rounded bg-black/60 px-1 text-[10px] leading-4 font-medium text-white">
          {count}
        </span>
      )}
    </div>
  )
}

function SyncFooter() {
  const sync = useSyncStatus()
  if (!sync) return null

  const { pendingCount, status } = sync
  const [tone, message] =
    pendingCount > 0
      ? [
          "bg-amber-500",
          `${pendingCount === 1 ? "1 change" : `${pendingCount} changes`} waiting. Open Stash on your Mac to sync.`,
        ]
      : status.reachable
        ? ["bg-emerald-500", "Synced with Stash for Mac"]
        : ["bg-muted-foreground/50", "Saved in this browser. Open Stash on your Mac to sync."]

  return (
    <footer className="flex items-center gap-2 border-t px-4 py-2.5 text-xs text-muted-foreground" role="status">
      <span className={`size-1.5 shrink-0 rounded-full ${tone}`} aria-hidden />
      {message}
    </footer>
  )
}

function EmptyLibrary() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 px-8 text-center">
      <div className="grid size-10 place-items-center rounded-full bg-muted">
        <Archive className="size-5 text-muted-foreground" aria-hidden />
      </div>
      <div className="space-y-1">
        <p className="text-sm font-medium">No saved posts yet</p>
        <p className="text-sm text-muted-foreground">Click the Stash button under any post on X to save it here.</p>
      </div>
      <Button variant="outline" size="sm" asChild>
        <a href="https://x.com" target="_blank" rel="noreferrer">
          Open X
        </a>
      </Button>
    </div>
  )
}
