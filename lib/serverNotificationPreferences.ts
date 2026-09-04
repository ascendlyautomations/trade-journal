import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  isCommentNotificationAllowed,
  isNotificationPreferenceEnabled,
  mapNotificationPreferencesRow,
  NOTIFICATION_PREFERENCES_SELECT,
  type CommentNotificationKind,
  type NotificationPreferenceKey,
  type NotificationPreferences,
} from "./notificationPreferences"

const SERVER_CACHE_TTL_MS = 60_000

type CacheEntry = {
  preferences: NotificationPreferences
  fetchedAt: number
}

const serverCache = new Map<string, CacheEntry>()

function isFresh(entry: CacheEntry | undefined): entry is CacheEntry {
  if (!entry) return false
  return Date.now() - entry.fetchedAt <= SERVER_CACHE_TTL_MS
}

export function invalidateServerNotificationPreferences(userId: string) {
  serverCache.delete(userId.trim())
}

function cachePreferences(userId: string, preferences: NotificationPreferences) {
  serverCache.set(userId, { preferences, fetchedAt: Date.now() })
}

/**
 * Load preferences for many recipients in one query.
 * Used by messaging fanout so we do not N+1 preference reads.
 */
export async function getServerNotificationPreferencesForUsers(
  userIds: string[],
  options?: { force?: boolean }
): Promise<Map<string, NotificationPreferences>> {
  const result = new Map<string, NotificationPreferences>()
  const unique = [
    ...new Set(userIds.map((id) => id.trim()).filter(Boolean)),
  ]
  if (unique.length === 0) return result

  const missing: string[] = []
  for (const id of unique) {
    if (!options?.force) {
      const cached = serverCache.get(id)
      if (isFresh(cached)) {
        result.set(id, cached.preferences)
        continue
      }
    }
    missing.push(id)
  }

  if (missing.length === 0) return result

  const { data, error } = await supabaseServiceRole
    .from("notification_preferences")
    .select(NOTIFICATION_PREFERENCES_SELECT)
    .in("user_id", missing)

  if (error) {
    console.error("[notification-preferences] batch fetch failed", error)
    for (const id of missing) {
      const fallback = mapNotificationPreferencesRow({ user_id: id }, id)
      cachePreferences(id, fallback)
      result.set(id, fallback)
    }
    return result
  }

  const found = new Set<string>()
  for (const row of data ?? []) {
    const id = String((row as { user_id?: string }).user_id ?? "").trim()
    if (!id) continue
    const preferences = mapNotificationPreferencesRow(
      row as Record<string, unknown>,
      id
    )
    cachePreferences(id, preferences)
    result.set(id, preferences)
    found.add(id)
  }

  for (const id of missing) {
    if (found.has(id)) continue
    const preferences = mapNotificationPreferencesRow({ user_id: id }, id)
    cachePreferences(id, preferences)
    result.set(id, preferences)
  }

  return result
}

export async function getServerNotificationPreferences(
  userId: string,
  options?: { force?: boolean }
): Promise<NotificationPreferences> {
  const key = userId.trim()
  if (!key) {
    return mapNotificationPreferencesRow(null, "")
  }

  if (!options?.force) {
    const cached = serverCache.get(key)
    if (isFresh(cached)) {
      return cached.preferences
    }
  }

  const map = await getServerNotificationPreferencesForUsers([key], {
    force: true,
  })
  return map.get(key) ?? mapNotificationPreferencesRow({ user_id: key }, key)
}

export async function isServerCommentNotificationAllowed(
  recipientUserId: string,
  kind: CommentNotificationKind,
  isAchievement: boolean
): Promise<boolean> {
  // Fresh read — comment inserts must not use a stale toggle.
  const prefs = await getServerNotificationPreferences(recipientUserId, {
    force: true,
  })
  return isCommentNotificationAllowed(prefs, kind, isAchievement)
}

function filterByKeys(
  prefsByUser: Map<string, NotificationPreferences>,
  recipientIds: string[],
  keys: NotificationPreferenceKey[]
): string[] {
  const allowed: string[] = []
  for (const recipientId of recipientIds) {
    const prefs =
      prefsByUser.get(recipientId) ??
      mapNotificationPreferencesRow({ user_id: recipientId }, recipientId)
    if (!prefs.notifications_enabled) continue
    if (keys.every((key) => isNotificationPreferenceEnabled(prefs, key))) {
      allowed.push(recipientId)
    }
  }
  return allowed
}

export async function filterRecipientsByRoomMessagePreference(
  recipientIds: string[]
): Promise<string[]> {
  if (recipientIds.length === 0) return []
  const prefsByUser = await getServerNotificationPreferencesForUsers(
    recipientIds,
    { force: true }
  )
  return filterByKeys(prefsByUser, recipientIds, ["room_messages_enabled"])
}

export async function filterRecipientsByRoomMentionPreference(
  recipientIds: string[]
): Promise<string[]> {
  if (recipientIds.length === 0) return []
  const prefsByUser = await getServerNotificationPreferencesForUsers(
    recipientIds,
    { force: true }
  )
  return filterByKeys(prefsByUser, recipientIds, ["room_mentions_enabled"])
}

export async function filterRecipientsByDirectMessagePreference(
  recipientIds: string[]
): Promise<string[]> {
  if (recipientIds.length === 0) return []
  const prefsByUser = await getServerNotificationPreferencesForUsers(
    recipientIds,
    { force: true }
  )
  return filterByKeys(prefsByUser, recipientIds, ["direct_messages_enabled"])
}

/**
 * DM / share / story-reply push preference for a specific message type.
 * Story replies and shared content use their dedicated Settings toggles.
 */
export async function filterRecipientsByDmMessageTypePreference(
  recipientIds: string[],
  messageType: string | null | undefined
): Promise<string[]> {
  if (recipientIds.length === 0) return []

  const type = String(messageType ?? "").trim()
  let key: NotificationPreferenceKey = "direct_messages_enabled"
  if (type === "story_reply") {
    key = "story_replies_enabled"
  } else if (
    type === "story_share" ||
    type === "trade" ||
    type === "post" ||
    type === "profile_post" ||
    type === "achievement_post"
  ) {
    key = "shares_enabled"
  }

  const prefsByUser = await getServerNotificationPreferencesForUsers(
    recipientIds,
    { force: true }
  )
  return filterByKeys(prefsByUser, recipientIds, [key])
}
