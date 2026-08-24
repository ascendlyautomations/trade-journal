import { after } from "next/server"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { scheduleIosPushDelivery } from "@/lib/server/push/deliverPushNotification"
import { scheduleMessagingPush } from "@/lib/server/push/messagingPush"
import { scheduleDmConversationPush } from "@/lib/server/push/dmConversationPush"
import type { DeliverPushInput } from "@/lib/server/push/deliverPushNotification"
import type { MessagingPushInput } from "@/lib/server/push/messagingPush"
import type { ScheduleDmConversationPushParams } from "@/lib/server/push/dmConversationPush"
import { invalidateAppIconBadgeCache } from "@/lib/server/push/badgeService"

export type ActivityInsertRow = {
  user_id: string
  sender_id: string | null
  type: string
  content?: string | null
  read?: boolean
  post_id?: string | null
  trade_id?: string | null
  profile_post_id?: string | null
  achievement_post_id?: string | null
  reel_id?: string | null
  comment_id?: string | null
  room_id?: string | null
  room_message_id?: string | null
}

export type EmitActivityResult =
  | { ok: true; deduplicated?: boolean; inserted: boolean }
  | { ok: false; error: string }

/**
 * Single Activity write + push schedule path.
 * Push uses Phase-1 after()/waitUntil via scheduleIosPushDelivery.
 * Pass `awaitPush: true` when already inside an `after()` (e.g. like milestones)
 * so delivery is awaited on the current lifetime instead of nesting another after().
 */
export async function emitActivityNotification(params: {
  row: ActivityInsertRow
  push: Omit<DeliverPushInput, "recipientUserId"> & { recipientUserId?: string }
  logLabel?: string
  awaitPush?: boolean
}): Promise<EmitActivityResult> {
  const { row, push, logLabel, awaitPush } = params
  const { error } = await supabaseServiceRole.from("notifications").insert(row)

  if (error) {
    if (error.code === "23505") {
      return { ok: true, deduplicated: true, inserted: false }
    }
    if (logLabel) console.error(`[${logLabel}] insert failed`, error)
    return { ok: false, error: error.message }
  }

  invalidateAppIconBadgeCache(row.user_id)

  const pushInput: DeliverPushInput = {
    ...push,
    recipientUserId: push.recipientUserId ?? row.user_id,
    sender_id: push.sender_id !== undefined ? push.sender_id : row.sender_id,
    type: push.type ?? row.type,
    content: push.content !== undefined ? push.content : row.content,
  }

  if (awaitPush) {
    const { deliverIosPushNotification } = await import(
      "@/lib/server/push/deliverPushNotification"
    )
    await deliverIosPushNotification(pushInput)
  } else {
    scheduleIosPushDelivery(pushInput)
  }

  return { ok: true, inserted: true }
}

/** Messaging-only push (no Activity row). */
export function emitMessagingPush(input: MessagingPushInput): void {
  scheduleMessagingPush(input)
}

/** DM push batch via after() — same lifetime model as notify-dm. */
export function emitDmPushes(
  jobs: ScheduleDmConversationPushParams[]
): void {
  if (jobs.length === 0) return
  after(async () => {
    await Promise.all(jobs.map((job) => scheduleDmConversationPush(job)))
  })
}
