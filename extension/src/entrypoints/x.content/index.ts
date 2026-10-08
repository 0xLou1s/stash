import "./style.css"

import { getBookmarks, requestRemove, requestSave, watchBookmarks, type Media } from "@/lib/bookmarks"
import { readCapturedMedia } from "@/lib/x-media"
import { parsePost, postIdOf } from "./parse"
import { BUTTON_CLASS, bookmarkSlot, createButton, insertButtonAfter, renderButton, showToast } from "./ui"

/** Adds a Stash button right after X's own bookmark button on every post. */
export default defineContentScript({
  matches: ["https://x.com/*", "https://twitter.com/*"],
  async main(ctx) {
    const savedIds = new Set<string>()
    const capturedMedia = new Map<string, Media[]>()

    // Media details from x-media.content.ts, which reads X's own responses.
    ctx.addEventListener(window, "message", (event: MessageEvent<unknown>) => {
      if (event.source !== window) return
      for (const [id, media] of readCapturedMedia(event.data)) capturedMedia.set(id, media)
    })

    const render = (button: HTMLButtonElement) => renderButton(button, savedIds.has(button.dataset.postId ?? ""))
    const renderAll = () => document.querySelectorAll<HTMLButtonElement>(`.${BUTTON_CLASS}`).forEach(render)

    const toggle = async (button: HTMLButtonElement) => {
      const id = button.dataset.postId
      if (!id) return

      try {
        if (savedIds.has(id)) {
          await requestRemove(id)
          showToast("Removed from Stash")
        } else {
          // Read the post at click time: X recycles DOM nodes as you scroll.
          const article = button.closest("article")
          const bookmark = article && parsePost(article, capturedMedia.get(id))
          if (!bookmark) throw new Error("Couldn't read this post")
          await requestSave(bookmark)
          showToast("Saved to Stash")
        }
      } catch (error) {
        console.error("[Stash]", error)
        showToast("Couldn't update Stash. Reload the page and try again.")
      }
    }

    const enhance = (article: HTMLElement) => {
      const id = postIdOf(article)
      if (!id) return

      // X reuses article elements for other posts as you scroll.
      const existing = article.querySelector<HTMLButtonElement>(`.${BUTTON_CLASS}`)
      if (existing) {
        if (existing.dataset.postId !== id) {
          existing.dataset.postId = id
          render(existing)
        }
        return
      }

      const slot = bookmarkSlot(article)
      if (!slot) return
      const button = createButton(id, (button) => void toggle(button))
      render(button)
      insertButtonAfter(slot, button)
    }

    let scheduled = false
    const scan = () => {
      if (scheduled) return
      scheduled = true
      ctx.requestAnimationFrame(() => {
        scheduled = false
        document.querySelectorAll<HTMLElement>('article[data-testid="tweet"]').forEach(enhance)
      })
    }

    // Keep buttons in sync with saves and removals from anywhere (e.g. the popup).
    const applySaved = (bookmarks: { id: string }[]) => {
      savedIds.clear()
      bookmarks.forEach(({ id }) => savedIds.add(id))
      renderAll()
    }
    applySaved(await getBookmarks())
    ctx.onInvalidated(watchBookmarks(applySaved))

    scan()
    const observer = new MutationObserver(scan)
    observer.observe(document.body, { childList: true, subtree: true })
    ctx.onInvalidated(() => observer.disconnect())
  },
})
