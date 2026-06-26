import type { StoriesByUserMap } from "@/lib/activeStories"

const DEFAULT_STALE_MS = 5 * 60 * 1000

type StoriesSessionEntry = {
  userIdsKey: string
  storiesByUser: StoriesByUserMap
  fetchedAt: number
}

let session: StoriesSessionEntry | null = null

export function readStoriesSession(userIdsKey: string): StoriesByUserMap | null {
  if (!session || session.userIdsKey !== userIdsKey) return null
  if (Date.now() - session.fetchedAt > DEFAULT_STALE_MS) {
    session = null
    return null
  }
  return session.storiesByUser
}

export function writeStoriesSession(userIdsKey: string, storiesByUser: StoriesByUserMap) {
  session = { userIdsKey, storiesByUser, fetchedAt: Date.now() }
}

export function invalidateStoriesSession() {
  session = null
}
