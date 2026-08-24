import type { SupabaseClient } from "@supabase/supabase-js"
import { subscribeNotificationChanges } from "./notificationRealtime.ts"
import {
  extractRoomIdFromNotification,
  isRoomNotificationType,
  shouldSkipUnreadIncrement,
  stableSortedRoomIds,
  type RoomUnreadPatch,
} from "./communityRoomUnreadLogic.ts"

export type { RoomUnreadPatch }

export type CommunityRoomUnreadContext = {
  userId: string
  getSelectedRoomId: () => string | null
  isRoomMarkedRead: (roomId: string) => boolean
  patchUnread: (patch: RoomUnreadPatch) => void
  reconcile: (roomIds: string[]) => Promise<void>
}

const RECONCILE_MIN_INTERVAL_MS = 5_000
const BACKGROUND_RECONCILE_THRESHOLD_MS = 60_000

function shouldSkipUnreadIncrementForContext(
  ctx: CommunityRoomUnreadContext,
  roomId: string
): boolean {
  return shouldSkipUnreadIncrement({
    roomId,
    selectedRoomId: ctx.getSelectedRoomId(),
    isRoomMarkedRead: ctx.isRoomMarkedRead,
  })
}

/**
 * Event-driven room sidebar unread — no fixed-interval polling.
 * Initial reconcile remains caller-owned (once after joined rooms load).
 * Does not subscribe until `roomIds` is non-empty (avoids empty channel churn).
 */
export function subscribeCommunityRoomUnreadRealtime(
  supabase: SupabaseClient,
  ctx: CommunityRoomUnreadContext,
  roomIds: readonly string[]
): () => void {
  const sortedRoomIds = stableSortedRoomIds(roomIds)
  let cancelled = false
  let needsReconcile = false
  let lastReconcileAt = 0
  let hiddenAt: number | null = null
  let reconcileInFlight = false
  let detachMessages: (() => void) | null = null

  const runReconcileOnce = async () => {
    if (cancelled || reconcileInFlight) return
    const now = Date.now()
    if (now - lastReconcileAt < RECONCILE_MIN_INTERVAL_MS) return
    if (sortedRoomIds.length === 0) return
    reconcileInFlight = true
    try {
      await ctx.reconcile(sortedRoomIds)
      lastReconcileAt = Date.now()
      needsReconcile = false
    } finally {
      reconcileInFlight = false
    }
  }

  const onMessageInsert = (
    roomId: string,
    payload: { new?: Record<string, unknown> }
  ) => {
    const senderId = payload.new?.user_id
    if (senderId != null && String(senderId) === ctx.userId) return
    if (shouldSkipUnreadIncrementForContext(ctx, roomId)) return
    ctx.patchUnread({ [roomId]: true })
  }

  if (sortedRoomIds.length > 0) {
    const channel = supabase.channel(`community-unread-${ctx.userId}`)

    for (const roomId of sortedRoomIds) {
      channel.on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "room_messages",
          filter: `room_id=eq.${roomId}`,
        },
        (payload) => {
          if (cancelled) return
          onMessageInsert(roomId, payload as { new?: Record<string, unknown> })
        }
      )
    }

    channel.subscribe((status) => {
      if (cancelled) return
      if (status === "SUBSCRIBED" && needsReconcile) {
        void runReconcileOnce()
      }
      if (
        status === "CHANNEL_ERROR" ||
        status === "TIMED_OUT" ||
        status === "CLOSED"
      ) {
        needsReconcile = true
      }
    })

    detachMessages = () => {
      void supabase.removeChannel(channel)
    }
  }

  const onVisibility = () => {
    if (document.visibilityState === "hidden") {
      hiddenAt = Date.now()
      return
    }
    const wasHiddenMs = hiddenAt != null ? Date.now() - hiddenAt : 0
    hiddenAt = null
    if (
      wasHiddenMs >= BACKGROUND_RECONCILE_THRESHOLD_MS &&
      needsReconcile
    ) {
      void runReconcileOnce()
    }
  }

  document.addEventListener("visibilitychange", onVisibility)

  const unsubNotifications = subscribeNotificationChanges(
    ctx.userId,
    ({ eventType, new: row }) => {
      if (cancelled) return
      if (eventType !== "INSERT" && eventType !== "UPDATE") return
      if (!row || !isRoomNotificationType(row.type)) return
      const roomId = extractRoomIdFromNotification(row)
      if (!roomId) return

      if (eventType === "UPDATE" && row.read === true) {
        ctx.patchUnread({ [roomId]: false })
        return
      }

      if (eventType === "INSERT" && row.read === false) {
        if (shouldSkipUnreadIncrementForContext(ctx, roomId)) return
        ctx.patchUnread({ [roomId]: true })
      }
    }
  )

  return () => {
    cancelled = true
    document.removeEventListener("visibilitychange", onVisibility)
    unsubNotifications()
    detachMessages?.()
  }
}

/** @internal tests */
export {
  isRoomNotificationType,
  extractRoomIdFromNotification,
  shouldSkipUnreadIncrement,
  stableSortedRoomIds,
} from "./communityRoomUnreadLogic.ts"
