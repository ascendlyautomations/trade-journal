import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  isCommentNotificationAllowed,
  isNotificationPreferenceEnabled,
  type CommentNotificationKind,
  type NotificationPreferenceKey,
} from "@/lib/notificationPreferences"
import { getServerNotificationPreferences } from "@/lib/serverNotificationPreferences"
import { isApnsConfigured, sendApnsAlert } from "@/lib/server/push/apns"
import {
  countAppIconBadge,
  invalidateAppIconBadgeCache,
} from "@/lib/server/push/badgeService"
import { categoryForNotificationType } from "@/lib/server/push/pushCategories"
import {
  buildPushAlertCopy,
  buildPushDeepLinkHref,
  type PushNotificationTarget,
} from "@/lib/server/push/pushCopy"

/**
 * Unified APNs push input. Callers supply recipient + notification metadata;
 * the dispatcher owns tokens, prefs, badge, payload assembly, and transport.
 */
export type PushDispatchInput = PushNotificationTarget & {
  recipientUserId: string
  /**
   * When set, this Settings key is enforced (messaging paths).
   * When omitted, Activity-style type → preference mapping is used.
   */
  preferenceKey?: NotificationPreferenceKey
}

function preferenceKeyForType(
  type: string,
  opts: {
    isAchievement: boolean
    commentKind?: CommentNotificationKind
  }
): NotificationPreferenceKey | "comment_kind" | null {
  switch (type) {
    case "like":
      return opts.isAchievement ? "achievement_likes_enabled" : "likes_enabled"
    case "like_milestone":
    case "like_batch":
      return opts.isAchievement ? "achievement_likes_enabled" : "likes_enabled"
    case "comment":
      return "comment_kind"
    case "follow":
    case "follow_batch":
      return "followers_enabled"
    case "follow_request":
      return "follow_requests_enabled"
    case "follow_request_accepted":
      return "follow_request_accepts_enabled"
    case "room_message":
      return "room_messages_enabled"
    case "room_mention":
      return "room_mentions_enabled"
    case "room_join":
      return "room_joins_enabled"
    case "message":
      return "direct_messages_enabled"
    case "trading_report":
      return "product_updates_enabled"
    case "affiliate_referral":
    case "affiliate_commission_earned":
      // No dedicated Settings toggle yet — master switch only.
      return null
    default:
      return null
  }
}

async function shouldDeliverPush(
  recipientUserId: string,
  input: PushDispatchInput
): Promise<boolean> {
  const prefs = await getServerNotificationPreferences(recipientUserId, {
    force: true,
  })
  if (!prefs.notifications_enabled) return false

  // Explicit messaging preference key (DM / room chat / story reply / share).
  if (input.preferenceKey) {
    return isNotificationPreferenceEnabled(prefs, input.preferenceKey)
  }

  // Activity-style mapping from notification type.
  // Always re-check category toggles: DB BEFORE INSERT triggers that return null
  // cancel the row without an error — so a "successful" insert does not guarantee
  // a notification (or push) should go out.
  const isAchievement = Boolean(input.achievement_post_id)
  const key = preferenceKeyForType(input.type, {
    isAchievement,
    commentKind: input.commentKind,
  })

  if (key === "comment_kind") {
    return isCommentNotificationAllowed(
      prefs,
      input.commentKind ?? "comment",
      isAchievement
    )
  }
  if (key == null) return true
  return isNotificationPreferenceEnabled(prefs, key)
}

async function loadSenderProfile(senderId: string | null | undefined): Promise<{
  username: string | null
  name: string | null
}> {
  if (!senderId) return { username: null, name: null }
  const { data } = await supabaseServiceRole
    .from("profiles")
    .select("username, name")
    .eq("id", senderId)
    .maybeSingle()
  return {
    username: data?.username != null ? String(data.username) : null,
    name: data?.name != null ? String(data.name) : null,
  }
}

async function removeInvalidToken(
  tokenId: string,
  deviceToken: string,
  reason: string
): Promise<number> {
  const normalized = deviceToken.trim().toLowerCase()
  // Quarantine before the DB round-trip so overlapping dispatches skip this token.
  if (normalized) quarantineRemovedToken(normalized)

  console.info("[push] Deleting token", {
    reason,
    tokenId,
    tokenPrefix: normalized.slice(0, 12),
  })
  const { data, error, count } = await supabaseServiceRole
    .from("device_push_tokens")
    .delete({ count: "exact" })
    .eq("id", tokenId)
    .select("id")

  const affected = count ?? data?.length ?? 0
  console.info(`[push] Delete affected rows = ${affected}`)

  if (error) {
    console.error("[push] failed to remove invalid token", error)
    return 0
  }

  if (affected === 0) {
    // Fallback: exact token match (legacy rows / id drift).
    const fallback = await supabaseServiceRole
      .from("device_push_tokens")
      .delete({ count: "exact" })
      .eq("device_token", deviceToken)
      .select("id")
    const fallbackAffected = fallback.count ?? fallback.data?.length ?? 0
    console.info(
      `[push] Delete affected rows (token fallback) = ${fallbackAffected}`
    )
    if (fallback.error) {
      console.error("[push] token fallback delete failed", fallback.error)
    }
    return fallbackAffected
  }

  return affected
}

/** Same-isolate quarantine so concurrent dispatches skip tokens already deleted. */
const removedTokenQuarantine = new Set<string>()

function quarantineRemovedToken(normalizedToken: string) {
  removedTokenQuarantine.add(normalizedToken)
  // Bound memory on warm Vercel isolates.
  if (removedTokenQuarantine.size > 2_000) {
    const first = removedTokenQuarantine.values().next().value
    if (first) removedTokenQuarantine.delete(first)
  }
}

function isQuarantinedToken(deviceToken: string): boolean {
  return removedTokenQuarantine.has(deviceToken.trim().toLowerCase())
}

function parseApnsMeta(content: string | null | undefined): {
  conversationId?: string
  roomId?: string
  roomSlug?: string
  threadId?: string
  collapseId?: string
  followRequestId?: string
} {
  if (!content?.trim()) return {}
  try {
    const parsed = JSON.parse(content) as Record<string, unknown>
    if (!parsed || typeof parsed !== "object") return {}
    const out: {
      conversationId?: string
      roomId?: string
      roomSlug?: string
      threadId?: string
      collapseId?: string
      followRequestId?: string
    } = {}
    if (typeof parsed.conversation_id === "string") {
      out.conversationId = parsed.conversation_id
    }
    if (typeof parsed.room_id === "string") out.roomId = parsed.room_id
    if (typeof parsed.room_slug === "string") out.roomSlug = parsed.room_slug
    if (typeof parsed.thread_id === "string") out.threadId = parsed.thread_id
    if (typeof parsed.collapse_id === "string") {
      out.collapseId = parsed.collapse_id
    }
    if (typeof parsed.follow_request_id === "string") {
      out.followRequestId = parsed.follow_request_id
    }
    return out
  } catch {
    return {}
  }
}

/**
 * Single APNs delivery pipeline for Activity and Messaging pushes.
 * Never throws to callers — safe inside after() / waitUntil.
 */
export async function dispatchPushNotification(
  input: PushDispatchInput
): Promise<void> {
  try {
    if (!isApnsConfigured()) {
      if (process.env.NODE_ENV === "development") {
        console.warn(
          "[push] APNs env not configured — skipping iOS delivery. Set APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY."
        )
      }
      return
    }

    const recipientUserId = input.recipientUserId?.trim()
    if (!recipientUserId) return

    const isFollow =
      input.type === "follow" || input.type === "follow_batch"

    const allowed = await shouldDeliverPush(recipientUserId, input)
    if (!allowed) {
      if (isFollow) {
        console.info("[follow-push] Push skipped by preferences", {
          recipientUserId,
          type: input.type,
        })
      }
      return
    }

    const { data: tokenRows, error: tokenErr } = await supabaseServiceRole
      .from("device_push_tokens")
      .select("id, device_token")
      .eq("user_id", recipientUserId)
      .eq("platform", "ios")

    if (tokenErr) {
      console.error("[push] token lookup failed", tokenErr)
      return
    }

    const tokens = (tokenRows ?? []).filter((row) => {
      const token = String(row.device_token ?? "").trim()
      if (!token || !row.id) return false
      if (isQuarantinedToken(token)) return false
      return true
    })

    console.info(`[push] Loaded ${tokens.length} tokens`, {
      recipientUserId,
      type: input.type,
      rawRows: tokenRows?.length ?? 0,
      quarantinedSkipped: (tokenRows?.length ?? 0) - tokens.length,
    })

    if (!tokens.length) {
      if (isFollow) {
        console.info("[follow-push] Recipient push token not found", {
          recipientUserId,
          type: input.type,
        })
      }
      return
    }

    if (isFollow) {
      console.info("[follow-push] Recipient push token found", {
        recipientUserId,
        type: input.type,
        tokenCount: tokens.length,
      })
    }

    invalidateAppIconBadgeCache(recipientUserId)

    const sender = await loadSenderProfile(input.sender_id)
    const target: PushNotificationTarget = {
      ...input,
      senderUsername: input.senderUsername ?? sender.username,
      senderName: input.senderName ?? sender.name,
      recipientUserId,
    }
    const copy = buildPushAlertCopy(target)
    const href = buildPushDeepLinkHref(target)
    const badge = await countAppIconBadge(recipientUserId)
    const category = categoryForNotificationType(input.type)

    const meta = parseApnsMeta(input.content)
    const isMessaging =
      input.type === "message" || input.type === "room_message"

    let conversationId: string | undefined
    let roomId: string | undefined
    let roomSlug: string | undefined
    let threadId: string | undefined
    let collapseId: string | undefined
    let followRequestId: string | undefined

    if (isMessaging) {
      conversationId = meta.conversationId
      roomId = meta.roomId
      roomSlug = meta.roomSlug
      threadId = meta.threadId
      collapseId = meta.collapseId
      // DM grouping only: stable APS thread-id. Do not set collapse-id — that
      // would replace prior alerts for the conversation instead of stacking.
      if (input.type === "message" && conversationId && !threadId) {
        threadId = `dm:${conversationId}`
      }
    } else {
      // Activity path historically only forwarded follow_request_id from content.
      followRequestId = meta.followRequestId
    }

    if (isFollow) {
      console.info("[follow-push] APNs send attempted", {
        recipientUserId,
        type: input.type,
        title: copy.title,
        href,
        tokenCount: tokens.length,
      })
    }

    await Promise.all(
      tokens.map(async (row) => {
        const tokenId = String(row.id ?? "").trim()
        const deviceToken = String(row.device_token ?? "").trim()
        if (!tokenId || !deviceToken) return
        if (isQuarantinedToken(deviceToken)) {
          console.info("[push] Skipping quarantined token", {
            tokenPrefix: deviceToken.slice(0, 12).toLowerCase(),
          })
          return
        }
        const senderId =
          typeof input.sender_id === "string" && input.sender_id.trim()
            ? input.sender_id.trim()
            : undefined
        const result = await sendApnsAlert(deviceToken, {
          title: copy.title,
          body: copy.body,
          href,
          badge,
          notificationType: input.type,
          category,
          conversationId,
          roomId,
          roomSlug,
          threadId,
          collapseId,
          followRequestId,
          senderId,
        })
        if (isFollow) {
          if (result.ok) {
            console.info("[follow-push] APNs success", {
              recipientUserId,
              type: input.type,
            })
          } else {
            console.error("[follow-push] APNs failure", {
              recipientUserId,
              type: input.type,
              status: result.status,
              reason: result.reason,
            })
          }
        }
        if (!result.ok && result.invalidToken) {
          console.info("[push] Removing stale APNs token:", result.reason)
          await removeInvalidToken(tokenId, deviceToken, result.reason)
        } else if (!result.ok && result.reason !== "apns_not_configured") {
          console.error("[push] APNs send failed", {
            status: result.status,
            reason: result.reason,
          })
        }
      })
    )
  } catch (err) {
    console.error("[push] dispatchPushNotification crashed", err)
  }
}
