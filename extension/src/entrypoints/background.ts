import { storage } from "#imports"

import { queueAllForSync, watchPendingChanges } from "@/lib/bookmarks"
import { syncNow } from "@/lib/sync"

const SYNC_ALARM = "stash-sync"

// Set once posts saved before sync existed have been queued.
const backfilledItem = storage.defineItem<boolean>("local:syncBackfilled", { fallback: false })

/** Delivers queued saves and removals to the Mac app whenever it's reachable. */
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

  // The popup asks for a sync when it opens.
  browser.runtime.onMessage.addListener((message: unknown) => {
    if ((message as { type?: string } | null)?.type === "sync") void syncNow()
  })

  void syncNow()
})
