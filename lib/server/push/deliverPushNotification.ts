import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  isCommentNotificationAllowed,
  isNotificationPreferenceEnabled,
  type CommentNotificationKind,
  type NotificationPreferenceKey,
} from "@/lib/notificationPreferences"
import { getServerNotificationPreferences } from "@/lib/serverNotificationPreferences"
import { isApnsConfigured, sendApnsAlert } from "@/lib/server/push/apns"
import { countAppIconBadge, invalidateAppIconBadgeCache } from "@/lib/server/push/messagingPush"
import { categoryForNotificationType } from "@/lib/server/push/pushCategories"
import {
  buildPushAlertCopy,
  buildPushDeepLinkHref,
  type PushNotificationTarget,
} from "@/lib/server/push/pushCopy"

export type DeliverPushInput = PushNotificationTarget & {
  recipientUserId: string
  /** When true, skip preference re-check (insert already gated). Still checks master. */
  prefsAlreadyChecked?: boolean
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
    case "affiliate_referral":
    case "affiliate_commission_earned":
    case "trading_report":
      // No dedicated toggle — master switch only (matches DB insert guard).
      return null
    default:
      return null
  }
}

async function shouldDeliverPush(
  recipientUserId: string,
  input: DeliverPushInput
): Promise<boolean> {
  const prefs = await getServerNotificationPreferences(recipientUserId)
  if (!prefs.notifications_enabled) return false

  // Always re-check category toggles. DB BEFORE INSERT triggers that return null
  // cancel the row without an error — so a "successful" insert API response does
  // not guarantee a notification (or push) should go out.
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

async function removeInvalidToken(deviceToken: string) {
  const { error } = await supabaseServiceRole
    .from("device_push_tokens")
    .delete()
    .eq("device_token", deviceToken)
  if (error) {
    console.error("[push] failed to remove invalid token", error)
  }
}

/**
 * Extends an existing in-app notification with an optional iOS APNs push.
 * Never throws to callers — safe to fire-and-forget after inserts.
 */
export async function deliverIosPushNotification(
  input: DeliverPushInput
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

    const allowed = await shouldDeliverPush(recipientUserId, input)
    if (!allowed) {
      if (input.type === "follow" || input.type === "follow_batch") {
        console.info("[follow-push] Push skipped by preferences", {
          recipientUserId,
          type: input.type,
        })
      }
      return
    }

    const { data: tokens, error: tokenErr } = await supabaseServiceRole
      .from("device_push_tokens")
      .select("device_token")
      .eq("user_id", recipientUserId)
      .eq("platform", "ios")

    if (tokenErr) {
      console.error("[push] token lookup failed", tokenErr)
      return
    }
    if (!tokens?.length) {
      if (input.type === "follow" || input.type === "follow_batch") {
        console.info("[follow-push] Recipient push token not found", {
          recipientUserId,
          type: input.type,
        })
      }
      return
    }

    if (input.type === "follow" || input.type === "follow_batch") {
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
    // App icon = Activity unread + Messages unread (independent sources).
    const badge = await countAppIconBadge(recipientUserId)
    const category = categoryForNotificationType(input.type)

    let followRequestId: string | undefined
    if (input.type === "follow_request" && input.content) {
      try {
        const parsed = JSON.parse(input.content) as { follow_request_id?: string }
        if (typeof parsed.follow_request_id === "string") {
          followRequestId = parsed.follow_request_id
        }
      } catch {
        /* ignore */
      }
    }

    if (input.type === "follow" || input.type === "follow_batch") {
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
        const deviceToken = String(row.device_token ?? "").trim()
        if (!deviceToken) return
        const result = await sendApnsAlert(deviceToken, {
          title: copy.title,
          body: copy.body,
          href,
          badge,
          notificationType: input.type,
          category,
          followRequestId,
        })
        if (input.type === "follow" || input.type === "follow_batch") {
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
          await removeInvalidToken(deviceToken)
        } else if (!result.ok && result.reason !== "apns_not_configured") {
          console.error("[push] APNs send failed", {
            status: result.status,
            reason: result.reason,
          })
        }
      })
    )
  } catch (err) {
    console.error("[push] deliverIosPushNotification crashed", err)
  }
}

/** Non-blocking wrapper — never delays notification API responses. */
export function scheduleIosPushDelivery(input: DeliverPushInput) {
  void deliverIosPushNotification(input)
}
