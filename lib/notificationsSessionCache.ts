/** Notifications center session cache — native silent paint + background sync. */

import { persistNotifications } from "@/lib/nativeSilentCacheBridge"

export type NotificationsSessionSnapshot = {
  userId: string
  notifications: any[]
  senderProfiles?: Record<string, any>
  fetchedAt: number
}

const sessions = new Map<string, NotificationsSessionSnapshot>()

export function readNotificationsSession(
  userId: string
): NotificationsSessionSnapshot | null {
  const key = userId.trim()
  if (!key) return null
  return sessions.get(key) ?? null
}

export function writeNotificationsSession(
  userId: string,
  notifications: any[],
  senderProfiles?: Record<string, any>
) {
  const key = userId.trim()
  if (!key) return
  const snapshot: NotificationsSessionSnapshot = {
    userId: key,
    notifications,
    senderProfiles,
    fetchedAt: Date.now(),
  }
  sessions.set(key, snapshot)
  persistNotifications(key, {
    notifications,
    senderProfiles,
  })
}

export function seedNotificationsSession(
  userId: string,
  payload: {
    notifications?: any[]
    senderProfiles?: Record<string, any>
  },
  fetchedAt: number
) {
  const key = userId.trim()
  if (!key || sessions.has(key)) return
  sessions.set(key, {
    userId: key,
    notifications: Array.isArray(payload.notifications)
      ? payload.notifications
      : [],
    senderProfiles: payload.senderProfiles,
    fetchedAt,
  })
}

export function clearNotificationsSessionsForUser(userId: string) {
  sessions.delete(userId.trim())
}

export function clearAllNotificationsSessions() {
  sessions.clear()
}
