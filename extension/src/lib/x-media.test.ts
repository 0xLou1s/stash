import { describe, expect, it } from "vitest"

import type { Media } from "./bookmarks"
import { CAPTURED_MEDIA_MESSAGE, extractMedia, isTrustedMedia, readCapturedMedia } from "./x-media"

const post = (id: string, media: unknown[], extra: object = {}) => ({
  rest_id: id,
  legacy: { extended_entities: { media }, ...extra },
})

describe("extractMedia", () => {
  it("reads photos at large size with their original dimensions", () => {
    const json = post("1", [
      { type: "photo", media_url_https: "https://pbs.twimg.com/media/A.jpg", original_info: { width: 1200, height: 800 } },
    ])

    expect(extractMedia(json)).toEqual({
      "1": [{ kind: "photo", url: "https://pbs.twimg.com/media/A.jpg?name=large", posterURL: null, width: 1200, height: 800 }],
    })
  })

  it("picks the highest-bitrate mp4 for videos and keeps the still as the poster", () => {
    const json = post("2", [
      {
        type: "video",
        media_url_https: "https://pbs.twimg.com/thumb/B.jpg",
        original_info: { width: 720, height: 1280 },
        video_info: {
          variants: [
            { content_type: "application/x-mpegURL", url: "https://video.twimg.com/b.m3u8" },
            { content_type: "video/mp4", bitrate: 632000, url: "https://video.twimg.com/b-low.mp4" },
            { content_type: "video/mp4", bitrate: 2176000, url: "https://video.twimg.com/b-high.mp4" },
          ],
        },
      },
    ])

    expect(extractMedia(json)["2"]).toEqual([
      {
        kind: "video",
        url: "https://video.twimg.com/b-high.mp4",
        posterURL: "https://pbs.twimg.com/thumb/B.jpg",
        width: 720,
        height: 1280,
      },
    ])
  })

  it("marks animated GIFs as gif", () => {
    const json = post("3", [
      {
        type: "animated_gif",
        media_url_https: "https://pbs.twimg.com/gif/C.jpg",
        video_info: { variants: [{ content_type: "video/mp4", bitrate: 0, url: "https://video.twimg.com/c.mp4" }] },
      },
    ])

    expect(extractMedia(json)["3"]?.[0]?.kind).toBe("gif")
  })

  it("falls back to the still image when a video has no mp4", () => {
    const json = post("4", [{ type: "video", media_url_https: "https://pbs.twimg.com/thumb/D.jpg", video_info: { variants: [] } }])

    expect(extractMedia(json)["4"]?.[0]).toMatchObject({ kind: "photo", url: "https://pbs.twimg.com/thumb/D.jpg" })
  })

  it("finds posts nested anywhere, including retweets and quotes", () => {
    const photo = { type: "photo", media_url_https: "https://pbs.twimg.com/media/E.jpg" }
    const json = {
      data: {
        timeline: [
          post("10", [], { retweeted_status_result: { result: post("11", [photo]) } }),
          { quoted: post("12", [photo]) },
        ],
      },
    }

    expect(Object.keys(extractMedia(json)).sort()).toEqual(["11", "12"])
  })

  it("ignores posts without media and non-object input", () => {
    expect(extractMedia(post("5", []))).toEqual({})
    expect(extractMedia(null)).toEqual({})
    expect(extractMedia("text")).toEqual({})
  })
})

describe("isTrustedMedia", () => {
  const media = (url: string, posterURL: string | null = null): Media => ({
    kind: "photo",
    url,
    posterURL,
    width: null,
    height: null,
  })

  it("accepts X's CDNs over https", () => {
    expect(isTrustedMedia(media("https://pbs.twimg.com/a.jpg"))).toBe(true)
    expect(isTrustedMedia(media("https://video.twimg.com/a.mp4", "https://pbs.twimg.com/a.jpg"))).toBe(true)
  })

  it("rejects other hosts, plain http, look-alike hosts and junk", () => {
    expect(isTrustedMedia(media("https://evil.example/a.jpg"))).toBe(false)
    expect(isTrustedMedia(media("http://pbs.twimg.com/a.jpg"))).toBe(false)
    expect(isTrustedMedia(media("https://twimg.com.evil.example/a.jpg"))).toBe(false)
    expect(isTrustedMedia(media("https://pbs.twimg.com/a.jpg", "https://evil.example/p.jpg"))).toBe(false)
    expect(isTrustedMedia(media("not a url"))).toBe(false)
  })
})

describe("readCapturedMedia", () => {
  const photo = { kind: "photo", url: "https://pbs.twimg.com/a.jpg", posterURL: null, width: 10, height: 20 }
  const message = (media: unknown) => ({ source: CAPTURED_MEDIA_MESSAGE, media })

  it("keeps well-formed media from X's CDN, with only the known fields", () => {
    const result = readCapturedMedia(message({ "123": [{ ...photo, extra: "<script>" }] }))

    expect(result.get("123")).toEqual([photo])
  })

  it.each([
    ["not a message", "hello"],
    ["the wrong source", { source: "other", media: { "1": [photo] } }],
    ["media that isn't an object", message("nope")],
    ["null media", message(null)],
  ])("ignores %s", (_, data) => {
    expect(readCapturedMedia(data).size).toBe(0)
  })

  it("skips items that are malformed or point elsewhere", () => {
    const result = readCapturedMedia(
      message({
        "1": [
          photo,
          { ...photo, kind: "hologram" },
          { ...photo, url: 42 },
          { ...photo, url: "https://evil.example/a.jpg" },
          { ...photo, posterURL: { not: "a string" } },
          null,
        ],
        "not-a-post-id": [photo],
        "2": "not a list",
      }),
    )

    expect([...result.keys()]).toEqual(["1"])
    expect(result.get("1")).toEqual([photo])
  })

  it("drops sizes that aren't positive numbers", () => {
    const result = readCapturedMedia(message({ "1": [{ ...photo, width: "big", height: -5 }] }))

    expect(result.get("1")?.[0]).toMatchObject({ width: null, height: null })
  })
})
