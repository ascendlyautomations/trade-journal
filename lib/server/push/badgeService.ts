import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { NOTIFICATION_INBOX_TYPES } from "@/lib/notificationEngagementTypes"

type BadgeCacheEntry = { value: number; fetchedAt: number }

const BADGE_CACHE_TTL_MS = 5_000
const badgeCache = new Map<string, BadgeCacheEntry>()

/**
 * Single backend owner of the iOS app-icon badge integer.
 *
 * Formula (SQL `get_app_icon_badge`):
 *   Activity inbox unread + unmuted DM unread
 * Room unread is intentionally excluded (inbox UI only).
 */
export function invalidateAppIconBadgeCache(userId?: string) {
  if (!userId) {
    badgeCache.clear()
    return
  }
  badgeCache.delete(userId.trim())
}

function isMissingBadgeRpc(error: { code?: string; message?: string }): boolean {
  const message = String(error.message ?? "").toLowerCase()
  return (
    error.code === "PGRST202" ||
    error.code === "42883" ||
    message.includes("could not find the function") ||
    message.includes("schema cache")
  )
}

async function fallbackCountActivityUnread(userId: string): Promise<number> {
  const { count, error } = await supabaseServiceRole
    .from("notifications")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("read", false)
    .in("type", [...NOTIFICATION_INBOX_TYPES])

  if (error) {
    console.error("[badge] activity unread fallback failed", error)
    return 0
  }
  return count ?? 0
}

async function fallbackCountDmUnread(userId: string): Promise<number> {
  const { data: parts, error: partsErr } = await supabaseServiceRole
    .from("conversation_participants")
    .select("conversation_id")
    .eq("user_id", userId)

  if (partsErr) {
    console.error("[badge] participants lookup fallback failed", partsErr)
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
    .select("conversation_id, notifications_enabled, last_read_at")
    .eq("user_id", userId)
    .in("conversation_id", conversationIds)

  if (prefsErr) {
    console.error("[badge] conversation prefs fallback failed", prefsErr)
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
          console.error("[badge] dm unread fallback failed", {
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

/** Temporary fallback until `get_app_icon_badge` is applied everywhere. */
async function fallbackGetAppIconBadge(userId: string): Promise<number> {
  const [activity, messages] = await Promise.all([
    fallbackCountActivityUnread(userId),
    fallbackCountDmUnread(userId),
  ])
  return Math.max(0, activity + messages)
}

/**
 * Canonical badge lookup. Prefer this over any client-side sum of unread stores.
 */
export async function getAppIconBadge(userId: string): Promise<number> {
  const id = userId.trim()
  if (!id) return 0

  const cached = badgeCache.get(id)
  if (cached && Date.now() - cached.fetchedAt <= BADGE_CACHE_TTL_MS) {
    return cached.value
  }

  const { data, error } = await supabaseServiceRole.rpc("get_app_icon_badge", {
    p_user_id: id,
  })

  let value = 0
  if (error) {
    if (isMissingBadgeRpc(error)) {
      console.warn(
        "[badge] get_app_icon_badge missing — using formula fallback"
      )
      value = await fallbackGetAppIconBadge(id)
    } else {
      console.error("[badge] get_app_icon_badge RPC failed", error)
      value = 0
    }
  } else {
    const raw =
      typeof data === "number"
        ? data
        : typeof data === "string"
          ? Number.parseInt(data, 10)
          : 0
    value = Number.isFinite(raw) ? Math.max(0, Math.floor(raw)) : 0
  }

  badgeCache.set(id, { value, fetchedAt: Date.now() })
  return value
}

/** @deprecated Use getAppIconBadge — kept for call-site compatibility. */
export async function countAppIconBadge(userId: string): Promise<number> {
  return getAppIconBadge(userId)
}

/**
 * @deprecated DM unread for badge lives inside get_app_icon_badge.
 * Kept for import compatibility during the refactor.
 */
export async function countServerUnreadDmMessages(
  userId: string
): Promise<number> {
  return fallbackCountDmUnread(userId)
}
