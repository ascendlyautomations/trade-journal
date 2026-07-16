import type { SupabaseClient } from "@supabase/supabase-js"
import {
  getDemoFollowersModalUsers,
  getDemoFollowingModalUsers,
  isDemoProfileId,
} from "@/lib/demo/demoProfile"
import { isDemoModeActive } from "@/lib/demo/demoMode"

export const FOLLOW_LIST_PAGE_SIZE = 10

export type FollowListKind = "followers" | "following"

export type FollowListUser = {
  id: string
  username: string | null
  avatar_url: string | null
  name: string | null
}

export type FollowListPageResult = {
  users: FollowListUser[]
  /** Next offset for the subsequent page request. */
  nextOffset: number
  hasMore: boolean
}

type FollowListCacheEntry = {
  users: FollowListUser[]
  nextOffset: number
  hasMore: boolean
}

const followListCache = new Map<string, FollowListCacheEntry>()

export function followListCacheKey(
  profileId: string,
  kind: FollowListKind
): string {
  return `${profileId}:${kind}`
}

export function getFollowListCache(
  profileId: string,
  kind: FollowListKind
): FollowListCacheEntry | null {
  return followListCache.get(followListCacheKey(profileId, kind)) ?? null
}

export function setFollowListCache(
  profileId: string,
  kind: FollowListKind,
  entry: FollowListCacheEntry
): void {
  followListCache.set(followListCacheKey(profileId, kind), entry)
}

/** Drop cached pages after profile change or follow/unfollow. */
export function invalidateFollowListCache(profileId?: string): void {
  if (!profileId) {
    followListCache.clear()
    return
  }
  followListCache.delete(followListCacheKey(profileId, "followers"))
  followListCache.delete(followListCacheKey(profileId, "following"))
}

function mapProfilesById(
  ids: string[],
  profiles: FollowListUser[] | null | undefined
): FollowListUser[] {
  const byId = new Map(
    (profiles ?? []).map((row) => [String(row.id), row] as const)
  )
  const users: FollowListUser[] = []
  for (const id of ids) {
    const row = byId.get(String(id))
    if (row) users.push(row)
  }
  return users
}

function sliceDemoUsers(
  all: FollowListUser[],
  offset: number,
  pageSize: number
): FollowListPageResult {
  const users = all.slice(offset, offset + pageSize)
  const nextOffset = offset + users.length
  return {
    users,
    nextOffset,
    hasMore: nextOffset < all.length,
  }
}

/**
 * Fetches one page of follower/following profiles for a user.
 * Ordered by relationship `created_at` descending for stable pagination.
 */
export async function fetchFollowListPage(
  supabase: SupabaseClient,
  profileId: string,
  kind: FollowListKind,
  offset: number,
  pageSize: number = FOLLOW_LIST_PAGE_SIZE
): Promise<FollowListPageResult> {
  if (isDemoModeActive() && isDemoProfileId(profileId)) {
    const all =
      kind === "followers"
        ? getDemoFollowersModalUsers(profileId)
        : getDemoFollowingModalUsers(profileId)
    return sliceDemoUsers(all, offset, pageSize)
  }

  if (kind === "followers") {
    const { data: rows, error } = await supabase
      .from("followers")
      .select("follower_id, created_at")
      .eq("following_id", profileId)
      .order("created_at", { ascending: false })
      .range(offset, offset + pageSize - 1)

    if (error) throw error

    const ids = [
      ...new Set(
        (rows ?? [])
          .map((row) => row.follower_id)
          .filter((id): id is string => Boolean(id))
      ),
    ]

    if (ids.length === 0) {
      return { users: [], nextOffset: offset, hasMore: false }
    }

    const { data: profiles, error: profileError } = await supabase
      .from("profiles")
      .select("id, username, avatar_url, name")
      .in("id", ids)

    if (profileError) throw profileError

    return {
      users: mapProfilesById(ids, profiles as FollowListUser[]),
      nextOffset: offset + (rows?.length ?? 0),
      hasMore: (rows?.length ?? 0) === pageSize,
    }
  }

  const { data: rows, error } = await supabase
    .from("followers")
    .select("following_id, created_at")
    .eq("follower_id", profileId)
    .order("created_at", { ascending: false })
    .range(offset, offset + pageSize - 1)

  if (error) throw error

  const ids = [
    ...new Set(
      (rows ?? [])
        .map((row) => row.following_id)
        .filter((id): id is string => Boolean(id))
    ),
  ]

  if (ids.length === 0) {
    return { users: [], nextOffset: offset, hasMore: false }
  }

  const { data: profiles, error: profileError } = await supabase
    .from("profiles")
    .select("id, username, avatar_url, name")
    .in("id", ids)

  if (profileError) throw profileError

  return {
    users: mapProfilesById(ids, profiles as FollowListUser[]),
    nextOffset: offset + (rows?.length ?? 0),
    hasMore: (rows?.length ?? 0) === pageSize,
  }
}
