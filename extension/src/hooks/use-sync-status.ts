import { useEffect, useState } from "react"

import { getPendingChanges, watchPendingChanges } from "@/lib/bookmarks"
import { syncStatusItem, type SyncStatus } from "@/lib/sync"

/** How many changes are waiting for the Mac app, and whether it was reachable last time. `null` while loading. */
export function useSyncStatus(): { pendingCount: number; status: SyncStatus } | null {
  const [pendingCount, setPendingCount] = useState<number | null>(null)
  const [status, setStatus] = useState<SyncStatus | null>(null)

  useEffect(() => {
    let active = true
    void Promise.all([getPendingChanges(), syncStatusItem.getValue()]).then(([pending, initialStatus]) => {
      if (!active) return
      setPendingCount(Object.keys(pending).length)
      setStatus(initialStatus)
    })
    const unwatchPending = watchPendingChanges((pending) => setPendingCount(Object.keys(pending).length))
    const unwatchStatus = syncStatusItem.watch(setStatus)
    return () => {
      active = false
      unwatchPending()
      unwatchStatus()
    }
  }, [])

  return pendingCount === null || status === null ? null : { pendingCount, status }
}
