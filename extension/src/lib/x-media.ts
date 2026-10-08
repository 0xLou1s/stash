import type { Media } from "./bookmarks"

/** `source` tag on window messages from the page-world media capture script. */
export const CAPTURED_MEDIA_MESSAGE = "stash:captured-media"

export interface CapturedMediaMessage {
  source: typeof CAPTURED_MEDIA_MESSAGE
  /** Post id -> its media, in display order. */
  media: Record<string, Media[]>
}

/**
 * Walks one of X's GraphQL responses and pulls out media for every post in it.
 * Posts appear as objects with a `rest_id` and `legacy.extended_entities.media`;
 * retweets and quotes nest their own post objects, which the walk also finds.
 */
export function extractMedia(json: unknown): Record<string, Media[]> {
  const found: Record<string, Media[]> = {}

  const visit = (node: unknown) => {
    if (Array.isArray(node)) {
      node.forEach(visit)
      return
    }
    if (!node || typeof node !== "object") return

    const post = node as { rest_id?: unknown; legacy?: { extended_entities?: { media?: unknown } } }
    const rawMedia = post.legacy?.extended_entities?.media
    if (typeof post.rest_id === "string" && Array.isArray(rawMedia)) {
      const media = rawMedia.map(toMedia).filter((item): item is Media => item !== null)
      if (media.length > 0) found[post.rest_id] = media
    }

    Object.values(node).forEach(visit)
  }

  visit(json)
  return found
}

interface RawMedia {
  type?: string
  media_url_https?: string
  original_info?: { width?: number; height?: number }
  video_info?: { variants?: { content_type?: string; bitrate?: number; url?: string }[] }
}

function toMedia(raw: RawMedia): Media | null {
  const image = raw.media_url_https
  if (!image) return null

  const width = raw.original_info?.width ?? null
  const height = raw.original_info?.height ?? null

  if (raw.type === "photo") {
    return { kind: "photo", url: `${image}?name=large`, posterURL: null, width, height }
  }

  // Videos and GIFs come in several mp4 bitrates; keep the best one.
  const best = (raw.video_info?.variants ?? [])
    .filter((variant) => variant.content_type === "video/mp4" && variant.url)
    .sort((a, b) => (b.bitrate ?? 0) - (a.bitrate ?? 0))[0]
  if (!best?.url) {
    return { kind: "photo", url: image, posterURL: null, width, height }
  }

  return {
    kind: raw.type === "animated_gif" ? "gif" : "video",
    url: best.url,
    posterURL: image,
    width,
    height,
  }
}

/** Accepts only media that points at X's own CDNs, since any page script can post messages. */
export function isTrustedMedia(media: Media): boolean {
  return [media.url, media.posterURL].every((url) => {
    if (url === null) return true
    try {
      const { protocol, hostname } = new URL(url)
      return protocol === "https:" && hostname.endsWith(".twimg.com")
    } catch {
      return false
    }
  })
}
