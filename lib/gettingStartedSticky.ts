import type {
  GettingStartedChecklistItemId,
  GettingStartedProgress,
} from "@/lib/gettingStartedChecklist"

export const GETTING_STARTED_COMPLETED_STORAGE_KEY =
  "tradetraxs_getting_started_completed_v1"

/** Last progress count acknowledged for step popups (1–4). */
export const GETTING_STARTED_PROGRESS_POPUP_COUNT_KEY =
  "tradetraxs_getting_started_progress_popup_count_v1"

/** Per-task progress popups already shown (never repeat on revisit). */
export const GETTING_STARTED_PROGRESS_POPUP_TASK_IDS_KEY =
  "tradetraxs_getting_started_progress_popup_task_ids_v1"

const ALL_ITEM_IDS: GettingStartedChecklistItemId[] = [
  "profile",
  "trade",
  "post",
  "follow",
  "room",
  "public",
]

const ACTION_ITEM_IDS: GettingStartedChecklistItemId[] = [
  "trade",
  "post",
  "follow",
  "room",
  "public",
]

function serverActionTasksComplete(progress: GettingStartedProgress): number {
  return progress.items.filter(
    (item) => ACTION_ITEM_IDS.includes(item.id) && item.complete
  ).length
}

function scopedKey(base: string, userId: string): string {
  return `${base}:${userId}`
}

function parseStoredCompletedIds(raw: string | null): Set<GettingStartedChecklistItemId> {
  if (!raw) return new Set()
  try {
    const parsed = JSON.parse(raw) as unknown
    if (!Array.isArray(parsed)) return new Set()
    return new Set(
      parsed.filter((id): id is GettingStartedChecklistItemId =>
        ALL_ITEM_IDS.includes(id as GettingStartedChecklistItemId)
      )
    )
  } catch {
    return new Set()
  }
}

export function readStickyCompletedItemIds(
  userId: string
): Set<GettingStartedChecklistItemId> {
  if (typeof window === "undefined") return new Set()
  try {
    return parseStoredCompletedIds(
      window.localStorage.getItem(
        scopedKey(GETTING_STARTED_COMPLETED_STORAGE_KEY, userId)
      )
    )
  } catch {
    return new Set()
  }
}

export function writeStickyCompletedItemIds(
  userId: string,
  ids: Set<GettingStartedChecklistItemId>
) {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(
      scopedKey(GETTING_STARTED_COMPLETED_STORAGE_KEY, userId),
      JSON.stringify([...ids])
    )
  } catch {
    /* ignore quota / private mode */
  }
}

export function readLastProgressPopupCount(userId: string): number | null {
  if (typeof window === "undefined") return null
  try {
    const raw = window.localStorage.getItem(
      scopedKey(GETTING_STARTED_PROGRESS_POPUP_COUNT_KEY, userId)
    )
    if (raw === null) return null
    const n = Number(raw)
    return Number.isFinite(n) ? n : null
  } catch {
    return null
  }
}

export function writeLastProgressPopupCount(userId: string, count: number) {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(
      scopedKey(GETTING_STARTED_PROGRESS_POPUP_COUNT_KEY, userId),
      String(count)
    )
  } catch {
    /* ignore quota / private mode */
  }
}

export function readShownProgressPopupTaskIds(
  userId: string
): Set<GettingStartedChecklistItemId> {
  if (typeof window === "undefined") return new Set()
  try {
    return parseStoredCompletedIds(
      window.localStorage.getItem(
        scopedKey(GETTING_STARTED_PROGRESS_POPUP_TASK_IDS_KEY, userId)
      )
    )
  } catch {
    return new Set()
  }
}

export function writeShownProgressPopupTaskIds(
  userId: string,
  ids: Set<GettingStartedChecklistItemId>
) {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(
      scopedKey(GETTING_STARTED_PROGRESS_POPUP_TASK_IDS_KEY, userId),
      JSON.stringify([...ids])
    )
  } catch {
    /* ignore quota / private mode */
  }
}

export function markProgressPopupShownForTasks(
  userId: string,
  taskIds: Iterable<GettingStartedChecklistItemId>
) {
  const shown = readShownProgressPopupTaskIds(userId)
  let changed = false
  for (const id of taskIds) {
    if (!shown.has(id)) {
      shown.add(id)
      changed = true
    }
  }
  if (changed) writeShownProgressPopupTaskIds(userId, shown)
}

/** Merge server-derived completion with sticky local milestones (never uncheck). */
export function applyStickyGettingStartedProgress(
  progress: GettingStartedProgress,
  userId: string,
  options?: { profilePostCount?: number }
): GettingStartedProgress {
  const sticky = readStickyCompletedItemIds(userId)
  let stickyChanged = false

  // Clear wrongly stickied "post" from when feed trade rows counted as posts.
  if (options?.profilePostCount === 0 && sticky.has("post")) {
    sticky.delete("post")
    stickyChanged = true
  }

  // DB is source of truth when no action tasks are complete — discard stale sticky.
  if (serverActionTasksComplete(progress) === 0) {
    for (const id of ACTION_ITEM_IDS) {
      if (sticky.has(id)) {
        sticky.delete(id)
        stickyChanged = true
      }
    }
  }

  for (const item of progress.items) {
    if (item.complete && !sticky.has(item.id)) {
      sticky.add(item.id)
      stickyChanged = true
    }
  }

  if (stickyChanged) {
    writeStickyCompletedItemIds(userId, sticky)
  }

  const items = progress.items.map((item) => ({
    ...item,
    complete: item.complete || sticky.has(item.id),
  }))

  const completedCount = items.filter((item) => item.complete).length

  return {
    items,
    completedCount,
    totalCount: progress.totalCount,
    allComplete: completedCount === progress.totalCount,
  }
}
