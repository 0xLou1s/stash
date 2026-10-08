import type { Media, NewBookmark } from "@/lib/bookmarks"

// X's class names are generated, so everything here keys off data-testid.

export function postIdOf(article: HTMLElement): string | null {
  return timestampLink(article)?.href.match(/\/status\/(\d+)/)?.[1] ?? null
}

/**
 * Reads a post out of its <article>. `captured` is media from X's own API
 * responses when we have it; otherwise media is read from the DOM, which
 * only exposes still images (videos play from blob: URLs).
 */
export function parsePost(article: HTMLElement, captured: Media[] | undefined): NewBookmark | null {
  const timestamp = timestampLink(article)
  const [, handle, id] = timestamp?.href.match(/^\/([^/]+)\/status\/(\d+)/) ?? []
  if (!timestamp || !handle || !id) return null

  const nameBlock = outsideQuote(article.querySelectorAll('[data-testid="User-Name"]'))[0]
  const textBlock = outsideQuote(article.querySelectorAll<HTMLElement>('[data-testid="tweetText"]'))[0]

  return {
    id,
    url: `https://x.com/${handle}/status/${id}`,
    author: {
      name: nameBlock?.querySelector("span")?.textContent?.trim() || handle,
      handle,
      avatarURL:
        outsideQuote(article.querySelectorAll<HTMLImageElement>('[data-testid="Tweet-User-Avatar"] img'))[0]?.src ??
        null,
    },
    text: textBlock?.innerText ?? "",
    media: captured ?? mediaFromDOM(article),
    postedAt: timestamp.time.getAttribute("datetime") ?? new Date().toISOString(),
  }
}

/**
 * The outer post's timestamp, which links to the post. A quote post also
 * contains the quoted post's timestamp, and on a post's own page the outer one
 * comes after the quote card, so "the first <time>" isn't reliable.
 */
function timestampLink(article: HTMLElement): { href: string; time: HTMLTimeElement } | null {
  for (const time of outsideQuote(article.querySelectorAll("time"))) {
    const href = time.closest('a[href*="/status/"]')?.getAttribute("href")
    if (href) return { href, time }
  }
  return null
}

// Quoted posts sit inside a div[role="link"] within the outer article.
function outsideQuote<T extends Element>(elements: NodeListOf<T>): T[] {
  return [...elements].filter((el) => !el.closest('article div[role="link"]'))
}

function mediaFromDOM(article: HTMLElement): Media[] {
  const photos = outsideQuote(article.querySelectorAll<HTMLImageElement>('[data-testid="tweetPhoto"] img'))
  const videos = outsideQuote(article.querySelectorAll<HTMLVideoElement>('[data-testid="videoPlayer"] video'))

  return [
    ...photos.map((img) => ({
      kind: "photo" as const,
      url: img.src.replace(/name=\w+/, "name=large"),
      posterURL: null,
      width: img.naturalWidth || null,
      height: img.naturalHeight || null,
    })),
    ...videos.flatMap((video) => {
      const playable = video.src.startsWith("https://")
      if (!playable && !video.poster) return []
      return [
        {
          kind: playable ? ("video" as const) : ("photo" as const),
          url: playable ? video.src : video.poster,
          posterURL: playable ? video.poster || null : null,
          width: video.videoWidth || null,
          height: video.videoHeight || null,
        },
      ]
    }),
  ]
}
