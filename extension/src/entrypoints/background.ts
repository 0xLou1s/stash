import { storage } from "#imports"

import {
  queueAllForSync,
  removeBookmark,
  saveBookmark,
  watchPendingChanges,
  type LibraryMessage,
  type LibraryReply,
} from "@/lib/bookmarks"
import { syncNow } from "@/lib/sync"

const SYNC_ALARM = "stash-sync"

// Set once posts saved before sync existed have been queued.
const backfilledItem = storage.defineItem<boolean>("local:syncBackfilled", { fallback: false })

/**
 * The only place saved posts are written (see bookmarks.ts), and delivers
 * queued saves and removals to the Mac app whenever it's reachable.
 */
export default defineBackground(() => {
  browser.runtime.onInstalled.addListener(async () => {
    if (!(await backfilledItem.getValue())) {
      await queueAllForSync()
      await backfilledItem.setValue(true)
    }
    void syncNow()
  })

  browser.runtime.onStartup.addListener(() => void syncNow())

  // Retry while the app is closed; Chrome allows alarms down to once a minute.
  void browser.alarms.create(SYNC_ALARM, { periodInMinutes: 1 })
  browser.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === SYNC_ALARM) void syncNow()
  })

  // New saves or removals from the content script or popup.
  watchPendingChanges(() => void syncNow())

  // Saves and removals from the content script and popup, and the popup's
  // request to sync when it opens. Only this extension's own scripts can send these.
  browser.runtime.onMessage.addListener((message: LibraryMessage, _sender, sendResponse: (reply: LibraryReply) => void) => {
    const work = handle(message)
    if (!work) return false
    work.then(
      () => sendResponse({ ok: true }),
      (error: unknown) => sendResponse({ ok: false, error: String(error) }),
    )
    return true // Answer asynchronously.
  })

  void syncNow()
})

function handle(message: LibraryMessage): Promise<void> | undefined {
  switch (message?.type) {
    case "save":
      return saveBookmark(message.bookmark)
    case "remove":
      return removeBookmark(message.id)
    case "sync":
      void syncNow()
      return Promise.resolve()
    default:
      return undefined
  }
}
