import { storage } from "#imports"

import { getBookmark, getPendingChanges, markDelivered, type PendingChange } from "./bookmarks"

/**
 * Where queued changes go. Today it's the Stash Mac app's local endpoint
 * (ExtensionBridge.swift, same port). The routes match the planned cloud
 * API, so moving to the cloud means changing this URL and adding auth.
 */
const APP_URL = "http://127.0.0.1:47811/v1"

export interface SyncStatus {
  /** Whether the last attempt reached the app. */
  reachable: boolean
  lastAttemptAt: string | null
  lastSyncedAt: string | null
}

export const syncStatusItem = storage.defineItem<SyncStatus>("local:syncStatus", {
  fallback: { reachable: false, lastAttemptAt: null, lastSyncedAt: null },
})

type Delivery = "delivered" | "rejected" | "unreachable"

let running: Promise<void> | null = null

/** Sends every queued change. Safe to call often; overlapping calls share one run. */
export function syncNow(): Promise<void> {
  running ??= drainQueue().finally(() => {
    running = null
  })
  return running
}

async function drainQueue(): Promise<void> {
  // Keep going until the queue is empty, so changes queued mid-run go out too.
  for (;;) {
    const pending = Object.entries(await getPendingChanges())
    if (pending.length === 0) {
      await recordAttempt(true)
      return
    }

    for (const [id, change] of pending) {
      const result = await deliver(id, change)
      if (result === "unreachable") {
        // The app isn't running. Leave the queue as is and try again later.
        await recordAttempt(false)
        return
      }
      if (result === "rejected") {
        console.warn(`[Stash] The app rejected ${change} for post ${id}; dropping it.`)
      }
      await markDelivered(id, change)
    }
  }
}

async function deliver(id: string, change: PendingChange): Promise<Delivery> {
  const url = `${APP_URL}/bookmarks/${encodeURIComponent(id)}`
  let response: Response

  try {
    if (change === "delete") {
      response = await fetch(url, { method: "DELETE" })
    } else {
      const bookmark = await getBookmark(id)
      if (!bookmark) return "delivered" // Removed since; its delete is queued instead.
      response = await fetch(url, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(bookmark),
      })
    }
  } catch {
    return "unreachable"
  }

  if (response.ok) return "delivered"
  // 4xx means this change will never be accepted as is; retrying won't help.
  return response.status >= 400 && response.status < 500 ? "rejected" : "unreachable"
}

async function recordAttempt(reachable: boolean): Promise<void> {
  const now = new Date().toISOString()
  const previous = await syncStatusItem.getValue()
  await syncStatusItem.setValue({
    reachable,
    lastAttemptAt: now,
    lastSyncedAt: reachable ? now : previous.lastSyncedAt,
  })
}
