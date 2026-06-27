import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  isCommentNotificationAllowed,
  mapNotificationPreferencesRow,
  NOTIFICATION_PREFERENCES_SELECT,
  type CommentNotificationKind,
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

export async function getServerNotificationPreferences(
  userId: string
): Promise<NotificationPreferences> {
  const key = userId.trim()
  if (!key) {
    return mapNotificationPreferencesRow(null, "")
  }

  const cached = serverCache.get(key)
  if (isFresh(cached)) {
    return cached.preferences
  }

  const { data, error } = await supabaseServiceRole
    .from("notification_preferences")
    .select(NOTIFICATION_PREFERENCES_SELECT)
    .eq("user_id", key)
    .maybeSingle()

  if (error) {
    console.error("[notification-preferences] server fetch failed", error)
    return mapNotificationPreferencesRow({ user_id: key }, key)
  }

  const preferences = mapNotificationPreferencesRow(data, key)
  serverCache.set(key, { preferences, fetchedAt: Date.now() })
  return preferences
}

export async function isServerCommentNotificationAllowed(
  recipientUserId: string,
  kind: CommentNotificationKind,
  isAchievement: boolean
): Promise<boolean> {
  const prefs = await getServerNotificationPreferences(recipientUserId)
  return isCommentNotificationAllowed(prefs, kind, isAchievement)
}

export async function filterRecipientsByRoomMessagePreference(
  recipientIds: string[]
): Promise<string[]> {
  if (recipientIds.length === 0) return []

  const allowed: string[] = []
  for (const recipientId of recipientIds) {
    const prefs = await getServerNotificationPreferences(recipientId)
    if (!prefs.notifications_enabled || !prefs.room_messages_enabled) continue
    allowed.push(recipientId)
  }
  return allowed
}
