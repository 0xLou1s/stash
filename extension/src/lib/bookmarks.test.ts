import { beforeEach, describe, expect, it } from "vitest"
import { fakeBrowser } from "wxt/testing/fake-browser"

import {
  getBookmarks,
  getPendingChanges,
  markDelivered,
  queueAllForSync,
  removeBookmark,
  saveBookmark,
  type NewBookmark,
} from "./bookmarks"

const post = (id: string): NewBookmark => ({
  id,
  url: `https://x.com/t/status/${id}`,
  author: { name: "T", handle: "t", avatarURL: null },
  text: `post ${id}`,
  media: [],
  postedAt: "2026-01-01T00:00:00.000Z",
})

beforeEach(() => {
  fakeBrowser.reset()
})

describe("saving and removing", () => {
  it("stores saved posts newest first and queues them for sync", async () => {
    await saveBookmark(post("1"))
    await new Promise((resolve) => setTimeout(resolve, 2)) // distinct savedAt
    await saveBookmark(post("2"))

    expect((await getBookmarks()).map((b) => b.id)).toEqual(["2", "1"])
    expect(await getPendingChanges()).toEqual({ "1": "upsert", "2": "upsert" })
  })

  it("replaces a queued save with a delete when the post is removed", async () => {
    await saveBookmark(post("1"))
    await removeBookmark("1")

    expect(await getBookmarks()).toEqual([])
    expect(await getPendingChanges()).toEqual({ "1": "delete" })
  })
})

describe("markDelivered", () => {
  it("clears a delivered change", async () => {
    await saveBookmark(post("1"))
    await markDelivered("1", "upsert")

    expect(await getPendingChanges()).toEqual({})
  })

  it("keeps a newer change queued while the older one was in flight", async () => {
    await saveBookmark(post("1"))
    await removeBookmark("1") // queued after the save started delivering
    await markDelivered("1", "upsert")

    expect(await getPendingChanges()).toEqual({ "1": "delete" })
  })
})

describe("queueAllForSync", () => {
  it("queues every saved post without overriding changes already queued", async () => {
    await saveBookmark(post("1"))
    await saveBookmark(post("2"))
    await markDelivered("1", "upsert")
    await markDelivered("2", "upsert")
    await removeBookmark("2")

    await queueAllForSync()

    expect(await getPendingChanges()).toEqual({ "1": "upsert", "2": "delete" })
  })
})

describe("concurrent writes", () => {
  it("doesn't lose a save queued while a delivery is being cleared", async () => {
    await saveBookmark(post("1"))

    // Both start before either finishes, as when the background script clears
    // a delivered change while the user saves another post.
    await Promise.all([markDelivered("1", "upsert"), saveBookmark(post("2"))])

    expect(await getPendingChanges()).toEqual({ "2": "upsert" })
    expect((await getBookmarks()).map((b) => b.id).sort()).toEqual(["1", "2"])
  })

  it("keeps every one of many simultaneous saves", async () => {
    await Promise.all(Array.from({ length: 20 }, (_, i) => saveBookmark(post(String(i)))))

    expect(await getBookmarks()).toHaveLength(20)
    expect(Object.keys(await getPendingChanges())).toHaveLength(20)
  })
})
