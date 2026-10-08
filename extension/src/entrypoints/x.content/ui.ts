// The Stash button and toast as they appear on x.com.

export const BUTTON_CLASS = "stash-button"

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

/** A Stash button for a post. `onToggle` runs on click instead of X opening the post. */
export function createButton(postId: string, onToggle: (button: HTMLButtonElement) => void): HTMLButtonElement {
  const button = document.createElement("button")
  button.type = "button"
  button.className = BUTTON_CLASS
  button.dataset.postId = postId
  button.addEventListener("click", (event) => {
    // The whole article is clickable; don't let X open the post.
    event.preventDefault()
    event.stopPropagation()
    onToggle(button)
  })
  return button
}

export function renderButton(button: HTMLButtonElement, saved: boolean): void {
  const label = saved ? "Remove from Stash" : "Save to Stash"
  button.setAttribute("aria-pressed", String(saved))
  button.setAttribute("aria-label", label)
  button.title = label
  button.innerHTML = saved ? ICON_SAVED : ICON_OUTLINE
}

/**
 * The action-bar slot holding X's bookmark button: the bookmark button's
 * ancestor that's a direct child of the action bar. Null if the post has none.
 */
export function bookmarkSlot(article: HTMLElement): Element | null {
  const bookmarkButton = article.querySelector('[data-testid="bookmark"], [data-testid="removeBookmark"]')
  const actionBar = bookmarkButton?.closest('[role="group"]')
  if (!bookmarkButton || !actionBar) return null

  let slot: Element = bookmarkButton
  while (slot.parentElement && slot.parentElement !== actionBar) slot = slot.parentElement
  return slot
}

/** Puts the button in its own slot right after `slot`, matching X's layout. */
export function insertButtonAfter(slot: Element, button: HTMLButtonElement): void {
  const wrapper = document.createElement("div")
  wrapper.className = "stash-slot"
  wrapper.append(button)
  slot.after(wrapper)
}

export function showToast(message: string): void {
  document.querySelector(".stash-toast")?.remove()
  const toast = document.createElement("div")
  toast.className = "stash-toast"
  toast.setAttribute("role", "status")
  toast.textContent = message
  document.body.append(toast)
  setTimeout(() => toast.remove(), 2000)
}
