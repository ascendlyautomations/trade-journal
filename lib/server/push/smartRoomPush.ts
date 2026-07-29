import {
  getOpenBatch,
  ROOM_DIGEST_COOLDOWN_MS,
  upsertOpenBatch,
} from "@/lib/server/push/batchWindows"
import { after } from "next/server"
import { flushPushBatch } from "@/lib/server/push/pushBatching"
import { scheduleMessagingPush } from "@/lib/server/push/messagingPush"

/**
 * Smart Trade Room generic message push:
 * - First message after quiet period → send immediately, start cooldown
 * - Additional messages during cooldown → accumulate; flush digest at window end
 * Mentions/replies must NOT call this (callers send immediate separately).
 */
export async function scheduleSmartRoomMessagePush(params: {
  recipientUserId: string
  senderId: string
  roomId: string
  content: string
}): Promise<"sent" | "batched"> {
  const batchKey = params.roomId
  const existing = await getOpenBatch(
    params.recipientUserId,
    "room_digest",
    batchKey
  )
  const now = Date.now()

  let payload: Record<string, unknown> = {}
  try {
    payload = JSON.parse(params.content) as Record<string, unknown>
  } catch {
    payload = {}
  }

  if (existing && now < new Date(existing.window_ends_at).getTime()) {
    const pending = Number(existing.meta.pending_count ?? 0) + 1
    await upsertOpenBatch({
      recipientUserId: params.recipientUserId,
      batchKind: "room_digest",
      batchKey,
      windowEndsAt: new Date(existing.window_ends_at),
      meta: {
        ...existing.meta,
        pending_count: pending,
        last_sender_id: params.senderId,
        content_template: params.content,
        room_name: payload.room_name ?? existing.meta.room_name,
        room_slug: payload.room_slug ?? existing.meta.room_slug,
      },
    })
    return "batched"
  }

  // Quiet period / expired → send this message immediately and open cooldown.
  scheduleMessagingPush({
    recipientUserId: params.recipientUserId,
    kind: "room_message",
    sender_id: params.senderId,
    content: params.content,
    preferenceKey: "room_messages_enabled",
    prefsAlreadyChecked: true,
  })

  const windowEndsAt = new Date(now + ROOM_DIGEST_COOLDOWN_MS)
  let upsert = await upsertOpenBatch({
    recipientUserId: params.recipientUserId,
    batchKind: "room_digest",
    batchKey,
    windowEndsAt,
    meta: {
      pending_count: 0,
      last_sender_id: params.senderId,
      content_template: params.content,
      room_name: payload.room_name ?? "Trade Room",
      room_slug: payload.room_slug ?? null,
    },
  })
  if (upsert.expiredRow) {
    // Flush any undelivered digest, then open a fresh cooldown window.
    await flushPushBatch(
      upsert.expiredRow.recipient_user_id,
      "room_digest",
      upsert.expiredRow.batch_key
    )
    upsert = await upsertOpenBatch({
      recipientUserId: params.recipientUserId,
      batchKind: "room_digest",
      batchKey,
      windowEndsAt,
      meta: {
        pending_count: 0,
        last_sender_id: params.senderId,
        content_template: params.content,
        room_name: payload.room_name ?? "Trade Room",
        room_slug: payload.room_slug ?? null,
      },
    })
  }

  after(async () => {
    await new Promise((resolve) =>
      setTimeout(resolve, ROOM_DIGEST_COOLDOWN_MS + 50)
    )
    await flushPushBatch(params.recipientUserId, "room_digest", batchKey)
  })

  return "sent"
}
