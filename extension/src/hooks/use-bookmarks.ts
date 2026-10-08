import { useEffect, useState } from "react"

import { getBookmarks, watchBookmarks, type Bookmark } from "@/lib/bookmarks"

/** Saved posts, newest first, kept live as they're saved or removed anywhere. `null` while loading. */
export function useBookmarks(): Bookmark[] | null {
  const [bookmarks, setBookmarks] = useState<Bookmark[] | null>(null)

  useEffect(() => {
    let active = true
    void getBookmarks().then((initial) => {
      if (active) setBookmarks(initial)
    })
    const unwatch = watchBookmarks(setBookmarks)
    return () => {
      active = false
      unwatch()
    }
  }, [])

  return bookmarks
}
