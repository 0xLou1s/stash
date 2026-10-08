import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { fakeBrowser } from "wxt/testing/fake-browser"

import { getPendingChanges, removeBookmark, saveBookmark, type NewBookmark } from "./bookmarks"
import { describeSync, syncNow, syncStatusItem, type SyncStatus } from "./sync"

const post = (id: string): NewBookmark => ({
  id,
  url: `https://x.com/t/status/${id}`,
  author: { name: "T", handle: "t", avatarURL: null },
  text: "",
  media: [],
  postedAt: "2026-01-01T00:00:00.000Z",
})

const status = (reachable: boolean): SyncStatus => ({ reachable, lastAttemptAt: null, lastSyncedAt: null })

describe("describeSync", () => {
  it("says how many changes are waiting", () => {
    expect(describeSync(1, status(true))).toEqual({
      state: "waiting",
      message: "1 change waiting. Open Stash on your Mac to sync.",
    })
    expect(describeSync(3, status(false)).message).toBe("3 changes waiting. Open Stash on your Mac to sync.")
  })

  it("reports synced only when the queue is empty and the app answered", () => {
    expect(describeSync(0, status(true)).state).toBe("synced")
    expect(describeSync(0, status(false)).state).toBe("local")
  })
})

describe("syncNow", () => {
  const fetchMock = vi.fn<typeof fetch>()

  /** The Stash app: answers health checks, and `status` for every change. */
  const stashAnswers = (status: number) =>
    fetchMock.mockImplementation(async (url) =>
      String(url).endsWith("/health")
        ? Response.json({ app: "Stash", ok: true })
        : new Response(null, { status }),
    )

  const changeRequests = () =>
    fetchMock.mock.calls.filter(([url]) => !String(url).endsWith("/health"))

  beforeEach(() => {
    fakeBrowser.reset()
    fetchMock.mockReset()
    vi.stubGlobal("fetch", fetchMock)
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("sends saves as PUT and removals as DELETE, then empties the queue", async () => {
    stashAnswers(204)
    await saveBookmark(post("1"))
    await saveBookmark(post("2"))
    await removeBookmark("2")

    await syncNow()

    const calls = changeRequests().map(([url, init]) => `${init?.method} ${url}`)
    expect(calls.sort()).toEqual([
      "DELETE http://127.0.0.1:47811/v1/bookmarks/2",
      "PUT http://127.0.0.1:47811/v1/bookmarks/1",
    ])
    expect(JSON.parse(String(fetchMock.mock.calls.find(([, init]) => init?.method === "PUT")?.[1]?.body))).toMatchObject({
      id: "1",
      savedAt: expect.any(String),
    })
    expect(await getPendingChanges()).toEqual({})
    expect((await syncStatusItem.getValue()).reachable).toBe(true)
  })

  it("keeps everything queued while the app isn't running", async () => {
    fetchMock.mockRejectedValue(new TypeError("Failed to fetch"))
    await saveBookmark(post("1"))

    await syncNow()

    expect(await getPendingChanges()).toEqual({ "1": "upsert" })
    expect((await syncStatusItem.getValue()).reachable).toBe(false)
  })

  it.each([403, 404, 500])("keeps the change queued when the app answers %i", async (status) => {
    stashAnswers(status)
    await saveBookmark(post("1"))

    await syncNow()

    expect(await getPendingChanges()).toEqual({ "1": "upsert" })
  })

  it("sends nothing when another program is on the app's port", async () => {
    fetchMock.mockImplementation(async () => Response.json({ hello: "not stash" }))
    await saveBookmark(post("1"))

    await syncNow()

    expect(changeRequests()).toEqual([])
    expect(await getPendingChanges()).toEqual({ "1": "upsert" })
    expect((await syncStatusItem.getValue()).reachable).toBe(false)
  })

  it("drops a change the app rejects, since retrying can't help", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {})
    stashAnswers(400)
    await saveBookmark(post("1"))

    await syncNow()

    expect(await getPendingChanges()).toEqual({})
  })
})
