import { beforeEach, describe, expect, it } from "vitest"

import type { Media } from "@/lib/bookmarks"
import { parsePost, postIdOf } from "./parse"

// Trimmed copies of the markup X renders; only the data-testid hooks matter.
const quoteCard = `
  <div role="link" tabindex="0">
    <div data-testid="User-Name"><span>Quoted Person</span><time datetime="2026-01-01T00:00:00Z">Jan 1</time></div>
    <div data-testid="tweetText">the quoted text</div>
    <div data-testid="tweetPhoto"><img src="https://pbs.twimg.com/media/Q.jpg?name=small"></div>
  </div>`

const actionBar = `<div role="group"><div><button data-testid="bookmark"></button></div></div>`

const timelineQuote = `<article data-testid="tweet">
  <div data-testid="Tweet-User-Avatar"><img src="https://pbs.twimg.com/profile_images/outer.jpg"></div>
  <div data-testid="User-Name"><span>Outer Author</span><a href="/outer/status/111"><time datetime="2026-02-02T00:00:00Z">2h</time></a></div>
  <div data-testid="tweetText">my take on this</div>
  ${quoteCard}
  ${actionBar}
</article>`

// On a post's own page the outer timestamp comes after the quote card.
const postPageQuote = `<article data-testid="tweet">
  <div data-testid="User-Name"><span>Outer Author</span><span>@outer</span></div>
  <div data-testid="tweetText">my take on this</div>
  ${quoteCard}
  <a href="/outer/status/111"><time datetime="2026-02-02T00:00:00Z">2:00 PM</time></a>
  ${actionBar}
</article>`

const photoPost = `<article data-testid="tweet">
  <div data-testid="User-Name"><span>Photographer</span><a href="/snap/status/222"><time datetime="2026-03-03T00:00:00Z">1h</time></a></div>
  <div data-testid="tweetPhoto"><img src="https://pbs.twimg.com/media/P.jpg?format=jpg&name=small"></div>
  ${actionBar}
</article>`

function mount(html: string): HTMLElement {
  document.body.innerHTML = html
  return document.querySelector("article")!
}

beforeEach(() => {
  document.body.innerHTML = ""
})

describe("parsePost", () => {
  it.each([
    ["timeline", timelineQuote],
    ["post page", postPageQuote],
  ])("reads the outer post of a quote post on the %s, not the quoted one", (_, html) => {
    const article = mount(html)

    expect(postIdOf(article)).toBe("111")
    expect(parsePost(article, undefined)).toMatchObject({
      id: "111",
      url: "https://x.com/outer/status/111",
      author: { name: "Outer Author", handle: "outer" },
      text: "my take on this",
      media: [],
      postedAt: "2026-02-02T00:00:00Z",
    })
  })

  it("reads photos from the page at large size when nothing was captured", () => {
    const bookmark = parsePost(mount(photoPost), undefined)

    expect(bookmark?.media).toEqual([
      {
        kind: "photo",
        url: "https://pbs.twimg.com/media/P.jpg?format=jpg&name=large",
        posterURL: null,
        width: null,
        height: null,
      },
    ])
  })

  it("prefers media captured from X's responses over the page", () => {
    const captured: Media[] = [
      { kind: "video", url: "https://video.twimg.com/v.mp4", posterURL: "https://pbs.twimg.com/v.jpg", width: 720, height: 1280 },
    ]

    expect(parsePost(mount(photoPost), captured)?.media).toEqual(captured)
  })

  it("drops media and avatars that don't point at X's CDN, whatever their source", () => {
    const article = mount(
      timelineQuote.replace("https://pbs.twimg.com/profile_images/outer.jpg", "https://evil.example/avatar.jpg"),
    )
    const captured: Media[] = [
      { kind: "photo", url: "https://evil.example/a.jpg", posterURL: null, width: null, height: null },
      { kind: "photo", url: "https://pbs.twimg.com/ok.jpg", posterURL: null, width: null, height: null },
    ]

    const bookmark = parsePost(article, captured)

    expect(bookmark?.author.avatarURL).toBeNull()
    expect(bookmark?.media.map((m) => m.url)).toEqual(["https://pbs.twimg.com/ok.jpg"])
  })

  it("returns null when the article has no linked timestamp", () => {
    const article = mount(`<article data-testid="tweet"><div data-testid="tweetText">ad</div></article>`)

    expect(postIdOf(article)).toBeNull()
    expect(parsePost(article, undefined)).toBeNull()
  })
})
