import { describe, expect, it, vi } from "vitest"

import { bookmarkSlot, createButton, insertButtonAfter, renderButton } from "./ui"

describe("bookmarkSlot", () => {
  it("returns the action bar's direct child that holds the bookmark button", () => {
    document.body.innerHTML = `<article>
      <div role="group">
        <div id="reply"></div>
        <div id="bookmark-slot"><span><button data-testid="bookmark"></button></span></div>
        <div id="share"></div>
      </div>
    </article>`

    expect(bookmarkSlot(document.querySelector("article")!)?.id).toBe("bookmark-slot")
  })

  it("also finds an already-bookmarked post", () => {
    document.body.innerHTML = `<article><div role="group"><div id="slot"><button data-testid="removeBookmark"></button></div></div></article>`

    expect(bookmarkSlot(document.querySelector("article")!)?.id).toBe("slot")
  })

  it("returns null for posts without an action bar", () => {
    document.body.innerHTML = `<article><div data-testid="tweetText">quote card</div></article>`

    expect(bookmarkSlot(document.querySelector("article")!)).toBeNull()
  })
})

describe("the Stash button", () => {
  it("goes right after the bookmark slot and shows its saved state", () => {
    document.body.innerHTML = `<div role="group"><div id="bookmark"></div><div id="share"></div></div>`
    const button = createButton("42", () => {})

    insertButtonAfter(document.getElementById("bookmark")!, button)
    renderButton(button, true)

    expect(document.getElementById("bookmark")!.nextElementSibling?.firstElementChild).toBe(button)
    expect(button.dataset.postId).toBe("42")
    expect(button.getAttribute("aria-pressed")).toBe("true")
    expect(button.getAttribute("aria-label")).toBe("Remove from Stash")

    renderButton(button, false)
    expect(button.getAttribute("aria-label")).toBe("Save to Stash")
  })

  it("handles the click itself so X doesn't open the post", () => {
    const onToggle = vi.fn()
    const button = createButton("42", onToggle)
    const article = document.createElement("article")
    const articleClick = vi.fn()
    article.addEventListener("click", articleClick)
    article.append(button)

    button.click()

    expect(onToggle).toHaveBeenCalledWith(button)
    expect(articleClick).not.toHaveBeenCalled()
  })
})
