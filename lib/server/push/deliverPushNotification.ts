import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { NOTIFICATION_INBOX_TYPES } from "@/lib/notificationEngagementTypes"
import {
  isCommentNotificationAllowed,
  isNotificationPreferenceEnabled,
  type CommentNotificationKind,
  type NotificationPreferenceKey,
} from "@/lib/notificationPreferences"
import { getServerNotificationPreferences } from "@/lib/serverNotificationPreferences"
import { isApnsConfigured, sendApnsAlert } from "@/lib/server/push/apns"
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
    case "comment":
      return "comment_kind"
    case "follow":
      return "followers_enabled"
    case "follow_request":
      return "follow_requests_enabled"
    case "room_message":
      return "room_messages_enabled"
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

async function countUnreadInbox(userId: string): Promise<number> {
  const { count, error } = await supabaseServiceRole
    .from("notifications")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("read", false)
    .in("type", [...NOTIFICATION_INBOX_TYPES])

  if (error) {
    console.error("[push] unread count failed", error)
    return 1
  }
  return count ?? 1
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
    if (!allowed) return

    const { data: tokens, error: tokenErr } = await supabaseServiceRole
      .from("device_push_tokens")
      .select("device_token")
      .eq("user_id", recipientUserId)
      .eq("platform", "ios")

    if (tokenErr) {
      console.error("[push] token lookup failed", tokenErr)
      return
    }
    if (!tokens?.length) return

    const sender = await loadSenderProfile(input.sender_id)
    const target: PushNotificationTarget = {
      ...input,
      senderUsername: input.senderUsername ?? sender.username,
      senderName: input.senderName ?? sender.name,
      recipientUserId,
    }
    const copy = buildPushAlertCopy(target)
    const href = buildPushDeepLinkHref(target)
    const badge = await countUnreadInbox(recipientUserId)

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
        })
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
