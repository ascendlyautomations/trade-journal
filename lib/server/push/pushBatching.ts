import { after } from "next/server"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { buildFeedDeepLinkHref } from "@/lib/feedDeepLink"
import { profilePath } from "@/lib/profileRoutes"
import {
  deleteBatch,
  formatBatchedFollowers,
  formatBatchedPeopleLine,
  getOpenBatch,
  LIKE_FOLLOW_BATCH_WINDOW_MS,
  listDueBatches,
  type PushBatchKind,
  type PushBatchRow,
  upsertOpenBatch,
} from "@/lib/server/push/batchWindows"
import { scheduleIosPushDelivery } from "@/lib/server/push/deliverPushNotification"
import { scheduleMessagingPush } from "@/lib/server/push/messagingPush"

type SenderRef = { id: string; name: string }

const FOLLOW_PUSH_LOG = "[follow-push]"

function displayFromProfile(row: {
  username?: string | null
  name?: string | null
}): string {
  const name = row.name?.trim()
  if (name) return name
  const username = row.username?.trim()
  if (username) return username.replace(/^@/, "")
  return "Someone"
}

async function loadSenderLabel(senderId: string): Promise<SenderRef> {
  const { data } = await supabaseServiceRole
    .from("profiles")
    .select("username, name")
    .eq("id", senderId)
    .maybeSingle()
  return {
    id: senderId,
    name: displayFromProfile(data ?? {}),
  }
}

function likeEntityFromTarget(target: Record<string, string | null | undefined>): {
  batchKey: string
  noun: string
  deepLink: string
  fields: Record<string, string>
} | null {
  if (target.comment_id) {
    return {
      batchKey: `comment:${target.comment_id}`,
      noun: "comment",
      deepLink: buildFeedDeepLinkHref({
        kind: target.reel_id
          ? "reel"
          : target.achievement_post_id
            ? "achievement"
            : target.trade_id && !target.post_id
              ? "trade"
              : "post",
        id: String(
          target.reel_id ||
            target.achievement_post_id ||
            target.trade_id ||
            target.post_id ||
            target.profile_post_id ||
            target.comment_id
        ),
        openComments: true,
      }),
      fields: Object.fromEntries(
        Object.entries(target).filter(([, v]) => v != null && String(v).trim())
      ) as Record<string, string>,
    }
  }
  if (target.reel_id) {
    return {
      batchKey: `reel:${target.reel_id}`,
      noun: "reel",
      deepLink: buildFeedDeepLinkHref({ kind: "reel", id: String(target.reel_id) }),
      fields: { reel_id: String(target.reel_id) },
    }
  }
  if (target.achievement_post_id) {
    return {
      batchKey: `achievement:${target.achievement_post_id}`,
      noun: "achievement",
      deepLink: buildFeedDeepLinkHref({
        kind: "achievement",
        id: String(target.achievement_post_id),
      }),
      fields: { achievement_post_id: String(target.achievement_post_id) },
    }
  }
  if (target.trade_id && !target.post_id && !target.profile_post_id) {
    return {
      batchKey: `trade:${target.trade_id}`,
      noun: "trade",
      deepLink: buildFeedDeepLinkHref({ kind: "trade", id: String(target.trade_id) }),
      fields: { trade_id: String(target.trade_id) },
    }
  }
  const postId = target.post_id || target.profile_post_id
  if (postId) {
    return {
      batchKey: `post:${postId}`,
      noun: "post",
      deepLink: buildFeedDeepLinkHref({ kind: "post", id: String(postId) }),
      fields: target.post_id
        ? { post_id: String(target.post_id) }
        : { profile_post_id: String(target.profile_post_id) },
    }
  }
  return null
}

function mergeSenders(
  existing: unknown,
  next: SenderRef
): SenderRef[] {
  const list = Array.isArray(existing) ? (existing as SenderRef[]) : []
  const byId = new Map(list.map((s) => [s.id, s]))
  byId.set(next.id, next)
  return [...byId.values()]
}

/**
 * Upsert a batch window. If an expired row blocks the insert, flush it first
 * (so pending pushes are not dropped), then create the new window.
 */
async function upsertBatchFlushingExpired(params: {
  recipientUserId: string
  batchKind: PushBatchKind
  batchKey: string
  windowEndsAt: Date
  meta: Record<string, unknown>
}): Promise<{ row: PushBatchRow | null; created: boolean }> {
  let result = await upsertOpenBatch(params)
  if (result.expiredRow) {
    console.info(`${FOLLOW_PUSH_LOG} Follow batch flushing expired before new window`, {
      recipientUserId: params.recipientUserId,
      batchKind: params.batchKind,
      batchKey: params.batchKey,
    })
    await flushPushBatch(
      result.expiredRow.recipient_user_id,
      result.expiredRow.batch_kind as PushBatchKind,
      result.expiredRow.batch_key
    )
    result = await upsertOpenBatch(params)
    if (result.expiredRow) {
      // Extreme race — force-delete and retry once more.
      await deleteBatch(
        params.recipientUserId,
        params.batchKind,
        params.batchKey
      )
      result = await upsertOpenBatch(params)
    }
  }
  return { row: result.row, created: result.created }
}

/**
 * Best-effort delayed flush for local/dev and long-lived runtimes.
 * Production delivery is guaranteed by the /api/push/flush-batches cron —
 * serverless isolates often cannot sleep for the full batch window.
 */
function scheduleDelayedFlush(
  recipientUserId: string,
  batchKind: PushBatchKind,
  batchKey: string,
  delayMs: number
) {
  after(async () => {
    try {
      await new Promise((resolve) => setTimeout(resolve, delayMs + 50))
      if (batchKind === "follow") {
        console.info(`${FOLLOW_PUSH_LOG} Follow batch flush timer fired`, {
          recipientUserId,
          batchKey,
        })
      }
      await flushPushBatch(recipientUserId, batchKind, batchKey)
    } catch (err) {
      console.error("[push-batch] delayed flush failed", {
        recipientUserId,
        batchKind,
        batchKey,
        error: err instanceof Error ? err.message : String(err),
      })
    }
  })
}

/** Enqueue a like for batched push. Activity row already inserted by caller. */
export async function enqueueLikePushBatch(params: {
  recipientUserId: string
  senderId: string
  notificationTarget: Record<string, string | null | undefined>
}): Promise<void> {
  const entity = likeEntityFromTarget(params.notificationTarget)
  if (!entity) {
    scheduleIosPushDelivery({
      recipientUserId: params.recipientUserId,
      type: "like",
      sender_id: params.senderId,
      prefsAlreadyChecked: true,
      ...params.notificationTarget,
    })
    return
  }

  const sender = await loadSenderLabel(params.senderId)
  const existing = await getOpenBatch(
    params.recipientUserId,
    "like",
    entity.batchKey
  )
  const now = Date.now()
  const stillOpen =
    existing != null && now < new Date(existing.window_ends_at).getTime()

  const senders = mergeSenders(stillOpen ? existing?.meta?.senders : [], sender)
  const windowEndsAt = stillOpen
    ? new Date(existing!.window_ends_at)
    : new Date(now + LIKE_FOLLOW_BATCH_WINDOW_MS)

  const { created } = await upsertBatchFlushingExpired({
    recipientUserId: params.recipientUserId,
    batchKind: "like",
    batchKey: entity.batchKey,
    windowEndsAt,
    meta: {
      senders,
      noun: entity.noun,
      deepLink: entity.deepLink,
      fields: entity.fields,
    },
  })

  if (created || !stillOpen) {
    scheduleDelayedFlush(
      params.recipientUserId,
      "like",
      entity.batchKey,
      LIKE_FOLLOW_BATCH_WINDOW_MS
    )
  }
}

export async function enqueueFollowPushBatch(params: {
  recipientUserId: string
  senderId: string
}): Promise<void> {
  console.info(`${FOLLOW_PUSH_LOG} Follow push scheduled`, {
    recipientUserId: params.recipientUserId,
    senderId: params.senderId,
  })

  const sender = await loadSenderLabel(params.senderId)
  const batchKey = "all"
  const existing = await getOpenBatch(params.recipientUserId, "follow", batchKey)
  const now = Date.now()
  const stillOpen =
    existing != null && now < new Date(existing.window_ends_at).getTime()

  const senders = mergeSenders(stillOpen ? existing?.meta?.senders : [], sender)
  const windowEndsAt = stillOpen
    ? new Date(existing!.window_ends_at)
    : new Date(now + LIKE_FOLLOW_BATCH_WINDOW_MS)

  const { created } = await upsertBatchFlushingExpired({
    recipientUserId: params.recipientUserId,
    batchKind: "follow",
    batchKey,
    windowEndsAt,
    meta: { senders },
  })

  if (created || !stillOpen) {
    console.info(`${FOLLOW_PUSH_LOG} Follow batch created`, {
      recipientUserId: params.recipientUserId,
      senderCount: senders.length,
      windowEndsAt: windowEndsAt.toISOString(),
    })
    scheduleDelayedFlush(
      params.recipientUserId,
      "follow",
      batchKey,
      LIKE_FOLLOW_BATCH_WINDOW_MS
    )
  } else {
    console.info(`${FOLLOW_PUSH_LOG} Follow batch updated`, {
      recipientUserId: params.recipientUserId,
      senderCount: senders.length,
      windowEndsAt: windowEndsAt.toISOString(),
    })
  }
}

export async function flushPushBatch(
  recipientUserId: string,
  batchKind: PushBatchKind,
  batchKey: string
): Promise<void> {
  const row = await getOpenBatch(recipientUserId, batchKind, batchKey)
  if (!row) return
  if (Date.now() < new Date(row.window_ends_at).getTime() - 25) {
    // Window not due yet (early call).
    return
  }

  try {
    if (batchKind === "like") {
      await flushLikeBatch(row)
    } else if (batchKind === "follow") {
      console.info(`${FOLLOW_PUSH_LOG} Follow batch flushed`, {
        recipientUserId,
        batchKey,
        senderCount: Array.isArray(row.meta.senders)
          ? (row.meta.senders as SenderRef[]).length
          : 0,
      })
      await flushFollowBatch(row)
    } else if (batchKind === "room_digest") {
      await flushRoomDigestBatch(row)
    } else if (batchKind === "dm") {
      // DM batches are delivered live via collapse-id; cron only cleans up.
    }
  } finally {
    await deleteBatch(recipientUserId, batchKind, batchKey)
  }
}

async function flushLikeBatch(row: PushBatchRow) {
  const senders = Array.isArray(row.meta.senders)
    ? (row.meta.senders as SenderRef[])
    : []
  const noun = String(row.meta.noun ?? "post")
  const fields = (row.meta.fields ?? {}) as Record<string, string>
  const deepLink = String(row.meta.deepLink ?? "/notifications")
  const copy = formatBatchedPeopleLine(
    senders.map((s) => s.name),
    `liked your ${noun}`
  )

  scheduleIosPushDelivery({
    recipientUserId: row.recipient_user_id,
    type: "like_batch",
    sender_id: senders[0]?.id ?? null,
    content: JSON.stringify({
      title: copy.title,
      body: copy.body.endsWith(".") ? copy.body : `${copy.body}.`,
      href: deepLink,
    }),
    prefsAlreadyChecked: false,
    ...fields,
  })
}

async function flushFollowBatch(row: PushBatchRow) {
  const senders = Array.isArray(row.meta.senders)
    ? (row.meta.senders as SenderRef[])
    : []
  const copy = formatBatchedFollowers(senders.map((s) => s.name))
  const href = senders[0]?.id
    ? profilePath({ id: senders[0].id })
    : "/notifications"

  console.info(`${FOLLOW_PUSH_LOG} Push payload generated`, {
    recipientUserId: row.recipient_user_id,
    type: "follow_batch",
    title: copy.title,
    href,
    senderCount: senders.length,
  })

  scheduleIosPushDelivery({
    recipientUserId: row.recipient_user_id,
    type: "follow_batch",
    sender_id: senders[0]?.id ?? null,
    content: JSON.stringify({
      title: copy.title,
      body: copy.body,
      href,
    }),
    prefsAlreadyChecked: false,
  })
}

async function flushRoomDigestBatch(row: PushBatchRow) {
  const pending = Number(row.meta.pending_count ?? 0)
  if (pending <= 0) return
  const roomName = String(row.meta.room_name ?? "Trade Room")
  const content = String(row.meta.content_template ?? "")
  const hrefContent = content
    ? content
    : JSON.stringify({
        room_slug: row.meta.room_slug ?? null,
        room_name: roomName,
        message_preview: `${pending} new messages`,
      })

  let payload: Record<string, unknown> = {}
  try {
    payload = JSON.parse(hrefContent) as Record<string, unknown>
  } catch {
    payload = {}
  }
  payload.message_preview =
    pending === 1 ? "1 new message" : `${pending} new messages`
  payload.is_digest = true

  scheduleMessagingPush({
    recipientUserId: row.recipient_user_id,
    kind: "room_message",
    sender_id: String(row.meta.last_sender_id ?? ""),
    content: JSON.stringify(payload),
    preferenceKey: "room_messages_enabled",
    prefsAlreadyChecked: true,
  })
}

/** Flush all due batches (cron / safety net). */
export async function flushAllDuePushBatches(): Promise<number> {
  const due = await listDueBatches(100)
  for (const row of due) {
    if (row.batch_kind === "follow") {
      console.info(`${FOLLOW_PUSH_LOG} Follow batch flushed`, {
        recipientUserId: row.recipient_user_id,
        batchKey: row.batch_key,
        via: "cron",
      })
    }
    await flushPushBatch(
      row.recipient_user_id,
      row.batch_kind as PushBatchKind,
      row.batch_key
    )
  }
  return due.length
}
