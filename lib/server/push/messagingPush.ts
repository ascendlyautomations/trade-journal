import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { NOTIFICATION_INBOX_TYPES } from "@/lib/notificationEngagementTypes"
import { isNotificationPreferenceEnabled } from "@/lib/notificationPreferences"
import { getServerNotificationPreferences } from "@/lib/serverNotificationPreferences"
import { isApnsConfigured, sendApnsAlert } from "@/lib/server/push/apns"
import {
  buildPushAlertCopy,
  buildPushDeepLinkHref,
  type PushNotificationTarget,
} from "@/lib/server/push/pushCopy"
import { categoryForNotificationType } from "@/lib/server/push/pushCategories"

export type MessagingPushKind = "message" | "room_message"

export type MessagingPushPreferenceKey =
  | "direct_messages_enabled"
  | "story_replies_enabled"
  | "shares_enabled"
  | "room_messages_enabled"

export type MessagingPushInput = {
  recipientUserId: string
  kind: MessagingPushKind
  sender_id: string
  content?: string | null
  /** When set, this Settings key is enforced (in addition to the master switch). */
  preferenceKey?: MessagingPushPreferenceKey
  /** @deprecated Prefer preferenceKey. Kept for call-site compatibility. */
  prefsAlreadyChecked?: boolean
  senderUsername?: string | null
  senderName?: string | null
}

type BadgeCacheEntry = { value: number; fetchedAt: number }

const BADGE_CACHE_TTL_MS = 5_000
const badgeCache = new Map<string, BadgeCacheEntry>()

export function invalidateAppIconBadgeCache(userId?: string) {
  if (!userId) {
    badgeCache.clear()
    return
  }
  badgeCache.delete(userId.trim())
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
    console.error("[messaging-push] failed to remove invalid token", error)
  }
}

async function countActivityUnread(userId: string): Promise<number> {
  const { count, error } = await supabaseServiceRole
    .from("notifications")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("read", false)
    .in("type", [...NOTIFICATION_INBOX_TYPES])

  if (error) {
    console.error("[messaging-push] activity unread count failed", error)
    return 0
  }
  return count ?? 0
}

/**
 * Server-side DM unread total for aps.badge (service role; no auth.uid() RPC).
 * Muted conversations (notifications_enabled = false) are excluded.
 */
export async function countServerUnreadDmMessages(
  userId: string
): Promise<number> {
  const { data: parts, error: partsErr } = await supabaseServiceRole
    .from("conversation_participants")
    .select("conversation_id")
    .eq("user_id", userId)

  if (partsErr) {
    console.error("[messaging-push] participants lookup failed", partsErr)
    return 0
  }

  const conversationIds = [
    ...new Set(
      (parts ?? [])
        .map((row) => String(row.conversation_id ?? "").trim())
        .filter(Boolean)
    ),
  ]
  if (conversationIds.length === 0) return 0

  const { data: prefRows, error: prefsErr } = await supabaseServiceRole
    .from("conversation_member_preferences")
    .select(
      "conversation_id, notifications_enabled, last_read_at, last_read_message_id"
    )
    .eq("user_id", userId)
    .in("conversation_id", conversationIds)

  if (prefsErr) {
    console.error("[messaging-push] conversation prefs lookup failed", prefsErr)
    return 0
  }

  const prefsByConversation = new Map(
    (prefRows ?? []).map((row) => [String(row.conversation_id), row])
  )

  const activeIds = conversationIds.filter((id) => {
    const pref = prefsByConversation.get(id)
    return pref?.notifications_enabled !== false
  })
  if (activeIds.length === 0) return 0

  let total = 0
  const chunkSize = 12
  for (let i = 0; i < activeIds.length; i += chunkSize) {
    const chunk = activeIds.slice(i, i + chunkSize)
    const counts = await Promise.all(
      chunk.map(async (conversationId) => {
        const pref = prefsByConversation.get(conversationId)
        let query = supabaseServiceRole
          .from("messages")
          .select("id", { count: "exact", head: true })
          .eq("conversation_id", conversationId)
          .not("sender_id", "is", null)
          .neq("sender_id", userId)

        if (pref?.last_read_at) {
          query = query.gt("created_at", pref.last_read_at)
        }

        const { count, error } = await query
        if (error) {
          console.error("[messaging-push] dm unread count failed", {
            conversationId,
            error,
          })
          return 0
        }
        return count ?? 0
      })
    )
    for (const n of counts) total += n
  }

  return total
}

/** App icon badge = Activity unread + Messages unread (independent sources). */
export async function countAppIconBadge(userId: string): Promise<number> {
  const cached = badgeCache.get(userId)
  if (cached && Date.now() - cached.fetchedAt <= BADGE_CACHE_TTL_MS) {
    return cached.value
  }

  const [activity, messages] = await Promise.all([
    countActivityUnread(userId),
    countServerUnreadDmMessages(userId),
  ])
  const value = Math.max(0, activity + messages)
  badgeCache.set(userId, { value, fetchedAt: Date.now() })
  return value
}

/**
 * Messaging-only APNs delivery — never inserts into public.notifications.
 */
export async function deliverMessagingPush(
  input: MessagingPushInput
): Promise<void> {
  try {
    if (!isApnsConfigured()) {
      if (process.env.NODE_ENV === "development") {
        console.warn(
          "[messaging-push] APNs env not configured — skipping iOS delivery."
        )
      }
      return
    }

    const recipientUserId = input.recipientUserId?.trim()
    if (!recipientUserId) return

    const prefs = await getServerNotificationPreferences(recipientUserId, {
      force: true,
    })
    if (!prefs.notifications_enabled) return

    const preferenceKey: MessagingPushPreferenceKey =
      input.preferenceKey ??
      (input.kind === "room_message"
        ? "room_messages_enabled"
        : "direct_messages_enabled")
    if (!isNotificationPreferenceEnabled(prefs, preferenceKey)) return

    const { data: tokens, error: tokenErr } = await supabaseServiceRole
      .from("device_push_tokens")
      .select("device_token")
      .eq("user_id", recipientUserId)
      .eq("platform", "ios")

    if (tokenErr) {
      console.error("[messaging-push] token lookup failed", tokenErr)
      return
    }
    if (!tokens?.length) return

    invalidateAppIconBadgeCache(recipientUserId)

    const sender = await loadSenderProfile(input.sender_id)
    const target: PushNotificationTarget = {
      type: input.kind,
      sender_id: input.sender_id,
      content: input.content,
      senderUsername: input.senderUsername ?? sender.username,
      senderName: input.senderName ?? sender.name,
      recipientUserId,
    }
    const copy = buildPushAlertCopy(target)
    const href = buildPushDeepLinkHref(target)
    const badge = await countAppIconBadge(recipientUserId)
    const category = categoryForNotificationType(input.kind)

    let conversationId: string | undefined
    let roomId: string | undefined
    let roomSlug: string | undefined
    let threadId: string | undefined
    let collapseId: string | undefined
    try {
      const parsed = input.content ? JSON.parse(input.content) : null
      if (parsed && typeof parsed === "object") {
        if (typeof parsed.conversation_id === "string") {
          conversationId = parsed.conversation_id
        }
        if (typeof parsed.room_id === "string") roomId = parsed.room_id
        if (typeof parsed.room_slug === "string") roomSlug = parsed.room_slug
        if (typeof parsed.thread_id === "string") threadId = parsed.thread_id
        if (typeof parsed.collapse_id === "string") {
          collapseId = parsed.collapse_id
        }
      }
    } catch {
      /* ignore */
    }

    // DM conversation coalescing: stable thread + collapse ids so rapid
    // messages replace the prior alert instead of stacking.
    if (input.kind === "message" && conversationId && !threadId) {
      threadId = `dm:${conversationId}`
      collapseId = threadId
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
          notificationType: input.kind,
          category,
          conversationId,
          roomId,
          roomSlug,
          threadId,
          collapseId,
        })
        if (!result.ok && result.invalidToken) {
          await removeInvalidToken(deviceToken)
        } else if (!result.ok && result.reason !== "apns_not_configured") {
          console.error("[messaging-push] APNs send failed", {
            status: result.status,
            reason: result.reason,
          })
        }
      })
    )
  } catch (err) {
    console.error("[messaging-push] deliverMessagingPush crashed", err)
  }
}

/** Non-blocking wrapper — never delays messaging API responses. */
export function scheduleMessagingPush(input: MessagingPushInput) {
  void deliverMessagingPush(input)
}
