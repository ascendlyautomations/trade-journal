/** Profile page session cache — survives route remounts for the same URL segment. */

const DEFAULT_STALE_MS = 5 * 60 * 1000

export type ProfileSessionSnapshot = {
  urlSegment: string
  profile: any
  room: any | null
  followersCount: number
  followingCount: number
  isFollowing: boolean
  isRequested: boolean
  followsYou: boolean
  allTrades: any[]
  wallPosts: any[]
  visibleTradeCount: number
  scrollY: number
  fetchedAt: number
}

const sessions = new Map<string, ProfileSessionSnapshot>()

export function readProfileSession(
  urlSegment: string
): ProfileSessionSnapshot | null {
  const key = urlSegment.trim()
  if (!key) return null
  const entry = sessions.get(key)
  if (!entry) return null
  if (Date.now() - entry.fetchedAt > DEFAULT_STALE_MS) {
    sessions.delete(key)
    return null
  }
  return entry
}

export function writeProfileSession(
  urlSegment: string,
  snapshot: Omit<ProfileSessionSnapshot, "urlSegment" | "fetchedAt">
) {
  const key = urlSegment.trim()
  if (!key) return
  sessions.set(key, {
    ...snapshot,
    urlSegment: key,
    fetchedAt: Date.now(),
  })
}

export function patchProfileSession(
  urlSegment: string,
  patch: Partial<Omit<ProfileSessionSnapshot, "urlSegment" | "fetchedAt">>
) {
  const key = urlSegment.trim()
  const prev = sessions.get(key)
  if (!prev) return
  sessions.set(key, { ...prev, ...patch, fetchedAt: Date.now() })
}

export function invalidateProfileSession(urlSegment: string) {
  sessions.delete(urlSegment.trim())
}

export function invalidateProfileSessionsForUser(profileUserId: string) {
  const id = String(profileUserId)
  for (const [key, session] of sessions) {
    if (String(session.profile?.id) === id) {
      sessions.delete(key)
    }
  }
}
