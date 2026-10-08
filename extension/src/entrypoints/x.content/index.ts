import "./style.css"

import { getBookmarks, removeBookmark, saveBookmark, watchBookmarks, type Media } from "@/lib/bookmarks"
import { CAPTURED_MEDIA_MESSAGE, isTrustedMedia, type CapturedMediaMessage } from "@/lib/x-media"
import { parsePost, postIdOf } from "./parse"

const BUTTON_CLASS = "stash-button"

const ICON_OUTLINE = `
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
       stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <rect x="3" y="4" width="18" height="4" rx="1"/>
    <path d="M5 8v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8"/>
    <path d="M10 12h4"/>
  </svg>`

const ICON_SAVED = `
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
       stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <rect x="3" y="4" width="18" height="4" rx="1" fill="currentColor"/>
    <path d="M5 8v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8"/>
    <path d="M9.5 13.5l2 2 3.5-3.5"/>
  </svg>`

/** Adds a Stash button right after X's own bookmark button on every post. */
export default defineContentScript({
  matches: ["https://x.com/*", "https://twitter.com/*"],
  async main(ctx) {
    const savedIds = new Set<string>()
    const capturedMedia = new Map<string, Media[]>()

    ctx.addEventListener(window, "message", (event: MessageEvent<CapturedMediaMessage>) => {
      if (event.source !== window || event.data?.source !== CAPTURED_MEDIA_MESSAGE) return
      for (const [id, media] of Object.entries(event.data.media)) {
        if (media.every(isTrustedMedia)) capturedMedia.set(id, media)
      }
    })

    const render = (button: HTMLButtonElement) => {
      const saved = savedIds.has(button.dataset.postId ?? "")
      const label = saved ? "Remove from Stash" : "Save to Stash"
      button.setAttribute("aria-pressed", String(saved))
      button.setAttribute("aria-label", label)
      button.title = label
      button.innerHTML = saved ? ICON_SAVED : ICON_OUTLINE
    }

    const renderAll = () => document.querySelectorAll<HTMLButtonElement>(`.${BUTTON_CLASS}`).forEach(render)

    const toggle = async (button: HTMLButtonElement) => {
      const id = button.dataset.postId
      if (!id) return

      try {
        if (savedIds.has(id)) {
          await removeBookmark(id)
          showToast("Removed from Stash")
        } else {
          // Read the post at click time: X recycles DOM nodes as you scroll.
          const article = button.closest("article")
          const bookmark = article && parsePost(article, capturedMedia.get(id))
          if (!bookmark) throw new Error("Couldn't read this post")
          await saveBookmark(bookmark)
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

      const existing = article.querySelector<HTMLButtonElement>(`.${BUTTON_CLASS}`)
      if (existing) {
        if (existing.dataset.postId !== id) {
          existing.dataset.postId = id
          render(existing)
        }
        return
      }

      const bookmarkButton = article.querySelector('[data-testid="bookmark"], [data-testid="removeBookmark"]')
      const actionBar = bookmarkButton?.closest('[role="group"]')
      if (!bookmarkButton || !actionBar) return

      // Climb to the bookmark button's direct child of the action bar,
      // so our button becomes a sibling slot right after it.
      let slot: Element = bookmarkButton
      while (slot.parentElement && slot.parentElement !== actionBar) slot = slot.parentElement

      const button = document.createElement("button")
      button.type = "button"
      button.className = BUTTON_CLASS
      button.dataset.postId = id
      button.addEventListener("click", (event) => {
        // The whole article is clickable; don't let X open the post.
        event.preventDefault()
        event.stopPropagation()
        void toggle(button)
      })
      render(button)

      const wrapper = document.createElement("div")
      wrapper.className = "stash-slot"
      wrapper.append(button)
      slot.after(wrapper)
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

function showToast(message: string) {
  document.querySelector(".stash-toast")?.remove()
  const toast = document.createElement("div")
  toast.className = "stash-toast"
  toast.setAttribute("role", "status")
  toast.textContent = message
  document.body.append(toast)
  setTimeout(() => toast.remove(), 2000)
}
