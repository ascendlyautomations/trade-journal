/** Leaderboard session cache — native silent paint + background sync. */

import { persistLeaderboard } from "@/lib/nativeSilentCacheBridge"

export type LeaderboardSessionSnapshot = {
  userId: string
  trades: any[]
  fetchedAt: number
}

const sessions = new Map<string, LeaderboardSessionSnapshot>()

export function readLeaderboardSession(
  userId: string
): LeaderboardSessionSnapshot | null {
  const key = userId.trim() || "__anonymous__"
  const entry = sessions.get(key)
  if (!entry) return null
  // Soft TTL 5 minutes — still return for paint; pages refresh in background.
  return entry
}

export function writeLeaderboardSession(userId: string, trades: any[]) {
  const key = userId.trim() || "__anonymous__"
  const snapshot: LeaderboardSessionSnapshot = {
    userId: key,
    trades,
    fetchedAt: Date.now(),
  }
  sessions.set(key, snapshot)
  persistLeaderboard(key, { trades })
}

export function seedLeaderboardSession(
  userId: string,
  payload: { trades?: any[] },
  fetchedAt: number
) {
  const key = userId.trim() || "__anonymous__"
  if (sessions.has(key)) return
  sessions.set(key, {
    userId: key,
    trades: Array.isArray(payload.trades) ? payload.trades : [],
    fetchedAt,
  })
}

export function clearLeaderboardSessionsForUser(userId: string) {
  sessions.delete(userId.trim() || "__anonymous__")
}

export function clearAllLeaderboardSessions() {
  sessions.clear()
}

export function isLeaderboardSessionFresh(userId: string, softTtlMs = 5 * 60_000) {
  const entry = readLeaderboardSession(userId)
  if (!entry) return false
  return Date.now() - entry.fetchedAt <= softTtlMs
}
