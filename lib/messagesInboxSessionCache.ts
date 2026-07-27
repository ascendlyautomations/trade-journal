/** Messages inbox session cache — survives route remounts for instant return visits. */

import { persistMessagesInbox } from "@/lib/nativeSilentCacheBridge"
import { isNativeIos } from "@/lib/nativePlatform"

const DEFAULT_STALE_MS = 5 * 60 * 1000

export type MessagesInboxSnapshot = {
  userId: string
  conversations: any[]
  fetchedAt: number
}

const sessions = new Map<string, MessagesInboxSnapshot>()

export function readMessagesInboxSession(
  userId: string
): MessagesInboxSnapshot | null {
  const key = userId.trim()
  if (!key) return null
  const entry = sessions.get(key)
  if (!entry) return null
  // Native: always paint cached inbox (SWR). Web: TTL miss.
  if (
    !(typeof window !== "undefined" && isNativeIos()) &&
    Date.now() - entry.fetchedAt > DEFAULT_STALE_MS
  ) {
    sessions.delete(key)
    return null
  }
  return entry
}

export function writeMessagesInboxSession(
  userId: string,
  conversations: any[]
) {
  const key = userId.trim()
  if (!key) return
  sessions.set(key, {
    userId: key,
    conversations,
    fetchedAt: Date.now(),
  })
  persistMessagesInbox(key, conversations)
}

export function seedMessagesInboxSession(
  userId: string,
  conversations: any[],
  fetchedAt: number
) {
  const key = userId.trim()
  if (!key) return
  const prev = sessions.get(key)
  if (prev && prev.fetchedAt >= fetchedAt) return
  sessions.set(key, {
    userId: key,
    conversations,
    fetchedAt,
  })
}

export function clearMessagesInboxSessionsForUser(userId: string) {
  sessions.delete(userId.trim())
}

export function clearAllMessagesInboxSessions() {
  sessions.clear()
}
