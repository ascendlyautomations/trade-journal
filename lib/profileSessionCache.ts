/** Profile page session cache — survives route remounts for the same URL segment. */

import { isNativeIos } from "@/lib/nativePlatform"
import { persistProfileSession } from "@/lib/nativeSilentCacheBridge"

const DEFAULT_STALE_MS = 5 * 60 * 1000

export type ProfileSessionSnapshot = {
  urlSegment: string
  profile: any
  room: any | null
  roomReady?: boolean
  followersCount: number
  followingCount: number
  isFollowing: boolean
  isRequested: boolean
  followsYou: boolean
  allTrades: any[]
  wallPosts: any[]
  wallPostsReady?: boolean
  visibleTradeCount: number
  tradeHasMore?: boolean
  tradesReady?: boolean
  profileReels?: unknown[]
  profileReelsReady?: boolean
  achievements?: unknown[]
  achievementsReady?: boolean
  analyticsTrades?: unknown[]
  analyticsTradesReady?: boolean
  summaryTrades?: unknown[]
  summaryReady?: boolean
  bootstrapPublicStats?: {
    total_trades: number
    wins: number
    total_pnl: number
  } | null
  bootstrapSectionCounts?: {
    has_active_story?: boolean
    has_room?: boolean
  } | null
  activeTab?: string
  selectedMode?: string
  scrollY: number
  fetchedAt: number
}

const sessions = new Map<string, ProfileSessionSnapshot>()

export function readProfileSession(
  urlSegment: string | undefined
): ProfileSessionSnapshot | null {
  const key = (urlSegment ?? "").trim()
  if (!key) return null
  const entry = sessions.get(key)
  if (!entry) return null
  if (Date.now() - entry.fetchedAt > DEFAULT_STALE_MS) {
    // Native: paint soft-stale profiles (5m soft window already elapsed → still OK).
    if (!(typeof window !== "undefined" && isNativeIos())) {
      sessions.delete(key)
      return null
    }
  }
  return entry
}

export function writeProfileSession(
  urlSegment: string | undefined,
  snapshot: Omit<ProfileSessionSnapshot, "urlSegment" | "fetchedAt">
) {
  const key = (urlSegment ?? "").trim()
  if (!key) return
  const full: ProfileSessionSnapshot = {
    ...snapshot,
    urlSegment: key,
    fetchedAt: Date.now(),
  }
  sessions.set(key, full)
  persistProfileSession(key, full)
}

export function seedProfileSession(
  urlSegment: string,
  snapshot: ProfileSessionSnapshot
) {
  const key = urlSegment.trim()
  if (!key || sessions.has(key)) return
  if (!snapshot || typeof snapshot !== "object") return
  sessions.set(key, { ...snapshot, urlSegment: key })
}

export function patchProfileSession(
  urlSegment: string | undefined,
  patch: Partial<Omit<ProfileSessionSnapshot, "urlSegment" | "fetchedAt">>
) {
  const key = (urlSegment ?? "").trim()
  const prev = sessions.get(key)
  if (!prev) return
  const next = { ...prev, ...patch, fetchedAt: Date.now() }
  sessions.set(key, next)
  persistProfileSession(key, next)
}

export function invalidateProfileSession(urlSegment: string) {
  sessions.delete(urlSegment.trim())
}

/** Copy a UUID-keyed snapshot under the canonical username before redirecting. */
export function aliasProfileSession(fromSegment: string, toSegment: string) {
  const fromKey = fromSegment.trim()
  const toKey = toSegment.trim()
  if (!fromKey || !toKey || fromKey === toKey) return
  const entry = sessions.get(fromKey)
  if (!entry) return
  if (
    Date.now() - entry.fetchedAt > DEFAULT_STALE_MS &&
    !(typeof window !== "undefined" && isNativeIos())
  ) {
    sessions.delete(fromKey)
    return
  }
  const aliased = {
    ...entry,
    urlSegment: toKey,
    fetchedAt: Date.now(),
  }
  sessions.set(toKey, aliased)
  persistProfileSession(toKey, aliased)
}

export function invalidateProfileSessionsForUser(profileUserId: string) {
  const id = String(profileUserId)
  for (const [key, session] of sessions) {
    if (String(session.profile?.id) === id) {
      sessions.delete(key)
    }
  }
}
