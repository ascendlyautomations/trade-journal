import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { emitActivityNotification } from "@/lib/server/notifications/emit"
import { getServerNotificationPreferences } from "@/lib/serverNotificationPreferences"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import type { SupabaseClient } from "@supabase/supabase-js"

export type NotifyResult = {
  ok: boolean
  skipped?: boolean | string
  deduplicated?: boolean
  reason?: string
  pushed?: number
  mentionsInserted?: number
  messagingPushed?: number
  error?: string
  status?: number
}

/**
 * High-level notification events. Routes authenticate and pass identifiers;
 * NotificationService owns insert / prefs / push orchestration.
 */
export type NotifyInput =
  | { type: "follow"; actorUserId: string; followingId: string }
  | { type: "follow_request"; actorUserId: string; targetId: string }
  | {
      type: "follow_request_accepted"
      actorUserId: string
      requesterId: string
    }
  | { type: "room_join"; actorUserId: string; roomId: string }
  | {
      type: "trading_report"
      actorUserId: string
      periodKey: string
      periodId: string
      kind?: "weekly" | "monthly"
      title?: string
      href?: string
    }
  | {
      type: "affiliate_referral"
      affiliateUserId: string
      referredUserId: string
      admin?: SupabaseClient
    }
  | {
      type: "affiliate_commission_earned"
      affiliateUserId: string
      referredUserId: string
      commissionAmount: number
      admin?: SupabaseClient
    }
  | { type: "like"; actorUserId: string; target: import("./handlers/likeNotify").LikeTarget }
  | { type: "comment"; actorUserId: string; commentId: string }
  | { type: "room_message"; actorUserId: string; messageId: string }
  | { type: "dm_message"; actorUserId: string; messageId: string }
  | {
      type: "like_milestone"
      ownerUserId: string
      actorUserId: string
      entity: import("@/lib/server/push/likeMilestones").LikeMilestoneEntity
    }

async function loadReferredUsername(referredUserId: string): Promise<string | null> {
  const { data } = await supabaseServiceRole
    .from("profiles")
    .select("username")
    .eq("id", referredUserId)
    .maybeSingle()
  const username = data?.username != null ? String(data.username).trim() : ""
  return username || null
}

/**
 * Single orchestration entry point for every notification type.
 */
export async function notify(input: NotifyInput): Promise<NotifyResult> {
  switch (input.type) {
    case "follow":
      return notifyFollow(input.actorUserId, input.followingId)
    case "follow_request":
      return notifyFollowRequest(input.actorUserId, input.targetId)
    case "follow_request_accepted":
      return notifyFollowRequestAccepted(input.actorUserId, input.requesterId)
    case "room_join":
      return notifyRoomJoin(input.actorUserId, input.roomId)
    case "trading_report":
      return notifyTradingReport(input)
    case "affiliate_referral":
      return notifyAffiliateReferral(input)
    case "affiliate_commission_earned":
      return notifyAffiliateCommission(input)
    case "like": {
      const { notifyLike } = await import("./handlers/likeNotify")
      return notifyLike(input.actorUserId, input.target)
    }
    case "comment": {
      const { notifyComment } = await import("./handlers/commentNotify")
      return notifyComment(input.actorUserId, input.commentId)
    }
    case "room_message": {
      const { notifyRoomMessage } = await import("./handlers/roomMessageNotify")
      return notifyRoomMessage(input.actorUserId, input.messageId)
    }
    case "dm_message": {
      const { notifyDmMessage } = await import("./handlers/dmNotify")
      return notifyDmMessage(input.actorUserId, input.messageId)
    }
    case "like_milestone": {
      const { maybeNotifyLikeMilestone } = await import(
        "@/lib/server/push/likeMilestones"
      )
      await maybeNotifyLikeMilestone({
        ownerUserId: input.ownerUserId,
        actorUserId: input.actorUserId,
        entity: input.entity,
      })
      return { ok: true }
    }
    default: {
      const _exhaustive: never = input
      return { ok: false, error: "Unknown notification type", status: 400 }
    }
  }
}

async function notifyFollow(
  actorUserId: string,
  followingId: string
): Promise<NotifyResult> {
  if (!followingId || followingId === actorUserId) {
    return { ok: false, error: "Invalid followingId", status: 400 }
  }

  const { data: followRow, error: followErr } = await supabaseServiceRole
    .from("followers")
    .select("follower_id")
    .eq("follower_id", actorUserId)
    .eq("following_id", followingId)
    .maybeSingle()

  if (followErr) {
    return { ok: false, error: followErr.message, status: 500 }
  }
  if (!followRow) {
    return { ok: false, error: "Follow relationship not found", status: 404 }
  }

  const result = await emitActivityNotification({
    row: {
      user_id: followingId,
      sender_id: actorUserId,
      type: "follow",
    },
    push: {
      recipientUserId: followingId,
      type: "follow",
      sender_id: actorUserId,
      prefsAlreadyChecked: true,
    },
    logLabel: "notifications/follow",
  })

  if (!result.ok) return { ok: false, error: result.error, status: 500 }
  if (result.deduplicated) return { ok: true, deduplicated: true }

  console.info("[follow-push] Follow activity created", {
    recipientUserId: followingId,
    senderId: actorUserId,
  })
  return { ok: true }
}

async function notifyFollowRequest(
  actorUserId: string,
  targetId: string
): Promise<NotifyResult> {
  if (!targetId || targetId === actorUserId) {
    return { ok: false, error: "Invalid targetId", status: 400 }
  }

  const { data: requestRow, error: requestErr } = await supabaseServiceRole
    .from("follow_requests")
    .select("id")
    .eq("requester_id", actorUserId)
    .eq("target_id", targetId)
    .eq("status", "pending")
    .maybeSingle()

  if (requestErr) {
    return { ok: false, error: requestErr.message, status: 500 }
  }
  if (!requestRow) {
    return { ok: false, error: "Pending follow request not found", status: 404 }
  }

  const content = JSON.stringify({ follow_request_id: requestRow.id })
  const result = await emitActivityNotification({
    row: {
      user_id: targetId,
      sender_id: actorUserId,
      type: "follow_request",
      content,
    },
    push: {
      recipientUserId: targetId,
      type: "follow_request",
      sender_id: actorUserId,
      content,
      prefsAlreadyChecked: true,
    },
    logLabel: "notifications/follow-request",
  })

  if (!result.ok) return { ok: false, error: result.error, status: 500 }
  if (result.deduplicated) return { ok: true, deduplicated: true }
  return { ok: true }
}

async function notifyFollowRequestAccepted(
  actorUserId: string,
  requesterId: string
): Promise<NotifyResult> {
  const prefs = await getServerNotificationPreferences(requesterId, {
    force: true,
  })
  if (!prefs.notifications_enabled || !prefs.follow_request_accepts_enabled) {
    return { ok: true, skipped: true, reason: "preferences" }
  }

  const result = await emitActivityNotification({
    row: {
      user_id: requesterId,
      sender_id: actorUserId,
      type: "follow_request_accepted",
    },
    push: {
      recipientUserId: requesterId,
      type: "follow_request_accepted",
      sender_id: actorUserId,
      prefsAlreadyChecked: true,
    },
    logLabel: "notifications/follow-request-accepted",
  })

  if (!result.ok) return { ok: false, error: result.error, status: 500 }
  if (result.deduplicated) return { ok: true, deduplicated: true }
  return { ok: true }
}

async function notifyRoomJoin(
  actorUserId: string,
  roomId: string
): Promise<NotifyResult> {
  if (!roomId) return { ok: false, error: "Invalid roomId", status: 400 }

  const { data: memberRow, error: memberErr } = await supabaseServiceRole
    .from("room_members")
    .select("id")
    .eq("room_id", roomId)
    .eq("user_id", actorUserId)
    .is("left_at", null)
    .maybeSingle()

  if (memberErr) return { ok: false, error: memberErr.message, status: 500 }
  if (!memberRow) {
    return { ok: false, error: "Active room membership not found", status: 404 }
  }

  const { data: roomRow, error: roomErr } = await supabaseServiceRole
    .from("rooms")
    .select("owner_user_id, name, slug")
    .eq("id", roomId)
    .maybeSingle()

  if (roomErr) return { ok: false, error: roomErr.message, status: 500 }
  if (!roomRow) return { ok: false, error: "Room not found", status: 404 }

  if (!roomRow.owner_user_id || roomRow.owner_user_id === actorUserId) {
    return { ok: true, skipped: true }
  }

  const content = JSON.stringify({
    room_slug: roomRow.slug ?? null,
    room_name: roomRow.name ?? null,
  })
  const ownerId = String(roomRow.owner_user_id)

  const result = await emitActivityNotification({
    row: {
      user_id: ownerId,
      sender_id: actorUserId,
      type: "room_join",
      room_id: roomId,
      content,
    },
    push: {
      recipientUserId: ownerId,
      type: "room_join",
      sender_id: actorUserId,
      room_id: roomId,
      content,
      prefsAlreadyChecked: true,
    },
    logLabel: "notifications/room-join",
  })

  if (!result.ok) return { ok: false, error: result.error, status: 500 }
  if (result.deduplicated) return { ok: true, deduplicated: true }
  return { ok: true }
}

async function notifyTradingReport(input: {
  actorUserId: string
  periodKey: string
  periodId: string
  kind?: "weekly" | "monthly"
  title?: string
  href?: string
}): Promise<NotifyResult> {
  const periodKey = input.periodKey.trim()
  const periodId = input.periodId.trim()
  const kind = input.kind === "monthly" ? "monthly" : "weekly"
  const title =
    input.title?.trim() ||
    (kind === "weekly" ? "Weekly trading report" : "Monthly trading report")
  const href =
    input.href?.trim() ||
    `/dashboard?report=${encodeURIComponent(periodKey || "weekly_last")}`

  if (!periodKey || !periodId) {
    return { ok: false, error: "Missing periodKey or periodId", status: 400 }
  }

  const content = JSON.stringify({
    title,
    body:
      kind === "weekly"
        ? "Your weekly trading summary is ready to review."
        : "Your monthly trading summary is ready to review.",
    href,
    periodKey,
    periodId,
    kind,
  })

  const { data: existing, error: existingErr } = await supabaseServiceRole
    .from("notifications")
    .select("id")
    .eq("user_id", input.actorUserId)
    .eq("type", "trading_report")
    .ilike("content", `%${periodId}%`)
    .limit(1)

  if (existingErr) {
    return { ok: false, error: existingErr.message, status: 500 }
  }
  if (existing && existing.length > 0) {
    return { ok: true, skipped: true, reason: "dedupe" }
  }

  const prefs = await getServerNotificationPreferences(input.actorUserId, {
    force: true,
  })
  if (!prefs.notifications_enabled || !prefs.product_updates_enabled) {
    return { ok: true, skipped: true, reason: "preferences" }
  }

  const result = await emitActivityNotification({
    row: {
      user_id: input.actorUserId,
      sender_id: null,
      type: "trading_report",
      content,
      read: false,
    },
    push: {
      recipientUserId: input.actorUserId,
      type: "trading_report",
      sender_id: null,
      content,
      prefsAlreadyChecked: true,
    },
    logLabel: "trading-reports/notify",
  })

  if (!result.ok) return { ok: false, error: result.error, status: 500 }
  return { ok: true }
}

async function notifyAffiliateReferral(input: {
  affiliateUserId: string
  referredUserId: string
}): Promise<NotifyResult> {
  const { affiliateUserId, referredUserId } = input
  if (!affiliateUserId || !referredUserId || affiliateUserId === referredUserId) {
    return { ok: true, skipped: true }
  }

  const username = await loadReferredUsername(referredUserId)
  const normalized = username ? normalizeProfileUsername(username) : ""
  const content = JSON.stringify({
    title: "New referral",
    body: normalized
      ? `@${normalized} signed up using your referral code.`
      : "A new user signed up using your referral code.",
    href: "/affiliate/dashboard",
  })

  const result = await emitActivityNotification({
    row: {
      user_id: affiliateUserId,
      sender_id: referredUserId,
      type: "affiliate_referral",
      content,
      read: false,
    },
    push: {
      recipientUserId: affiliateUserId,
      type: "affiliate_referral",
      sender_id: referredUserId,
      content,
      prefsAlreadyChecked: true,
    },
    logLabel: "affiliate-notification",
  })

  if (!result.ok) return { ok: false, error: result.error, status: 500 }
  if (result.deduplicated) return { ok: true, deduplicated: true }
  return { ok: true }
}

async function notifyAffiliateCommission(input: {
  affiliateUserId: string
  referredUserId: string
  commissionAmount: number
}): Promise<NotifyResult> {
  const { affiliateUserId, referredUserId, commissionAmount } = input
  if (!affiliateUserId || !referredUserId || affiliateUserId === referredUserId) {
    return { ok: true, skipped: true }
  }
  if (!Number.isFinite(commissionAmount) || commissionAmount <= 0) {
    return { ok: true, skipped: true }
  }

  const username = await loadReferredUsername(referredUserId)
  const normalized = username ? normalizeProfileUsername(username) : ""
  const amountStr = commissionAmount.toFixed(2)
  const content = JSON.stringify({
    title: "Commission earned",
    body: normalized
      ? `@${normalized} became a paying TraxPro subscriber. You earned $${amountStr}.`
      : `A referred user became a paying TraxPro subscriber. You earned $${amountStr}.`,
    href: "/affiliate/dashboard",
  })

  const result = await emitActivityNotification({
    row: {
      user_id: affiliateUserId,
      sender_id: referredUserId,
      type: "affiliate_commission_earned",
      content,
      read: false,
    },
    push: {
      recipientUserId: affiliateUserId,
      type: "affiliate_commission_earned",
      sender_id: referredUserId,
      content,
      prefsAlreadyChecked: true,
    },
    logLabel: "affiliate-notification",
  })

  if (!result.ok) return { ok: false, error: result.error, status: 500 }
  if (result.deduplicated) return { ok: true, deduplicated: true }
  return { ok: true }
}

/** Re-export emit helpers for handlers / tests. */
export { emitActivityNotification, emitDmPushes, emitMessagingPush } from "@/lib/server/notifications/emit"
