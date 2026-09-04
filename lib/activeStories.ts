import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import {
  getDemoFollowingIds,
  getDemoStoriesForUserIds,
  getDemoStoryBarProfiles,
} from "@/lib/demo/demoFeed"

/** Stories remain visible for 24 hours (matches feed + profile). */
export const STORY_WINDOW_MS = 24 * 60 * 60 * 1000

export const ACTIVE_STORIES_SELECT = "id, user_id, image_url, created_at"

export type ActiveStoryRow = {
  id: string
  user_id: string
  image_url: string
  created_at: string
}

export type StoriesByUserMap = Record<string, ActiveStoryRow[]>

export function isStoryActive(
  story: Pick<ActiveStoryRow, "created_at">,
  nowMs = Date.now()
): boolean {
  const created = new Date(story.created_at).getTime()
  return Number.isNaN(created) ? false : nowMs - created < STORY_WINDOW_MS
}

export function filterActiveStories<T extends ActiveStoryRow>(
  stories: T[],
  nowMs = Date.now()
): T[] {
  return stories.filter((story) => isStoryActive(story, nowMs))
}

export function groupActiveStoriesByUser(
  stories: ActiveStoryRow[]
): StoriesByUserMap {
  const map: StoriesByUserMap = {}

  for (const story of stories) {
    const uid = String(story.user_id)
    if (!map[uid]) map[uid] = []
    map[uid].push(story)
  }

  for (const uid of Object.keys(map)) {
    map[uid].sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )
  }

  return map
}

export function pruneExpiredStories(
  storiesByUser: StoriesByUserMap,
  nowMs = Date.now()
): StoriesByUserMap {
  const next: StoriesByUserMap = {}

  for (const [userId, stories] of Object.entries(storiesByUser)) {
    const active = filterActiveStories(stories, nowMs)
    if (active.length > 0) {
      next[userId] = active
    }
  }

  return next
}

export function userHasActiveStory(
  storiesByUser: StoriesByUserMap,
  userId: string | null | undefined
): boolean {
  if (!userId) return false
  return (storiesByUser[String(userId)]?.length ?? 0) > 0
}

export function getActiveStoriesForUser(
  storiesByUser: StoriesByUserMap,
  userId: string | null | undefined
): ActiveStoryRow[] {
  if (!userId) return []
  return storiesByUser[String(userId)] ?? []
}

/** Milliseconds until the next story expires, or null if none active. */
export function getSoonestStoryExpiryMs(
  storiesByUser: StoriesByUserMap,
  nowMs = Date.now()
): number | null {
  let soonest: number | null = null

  for (const stories of Object.values(storiesByUser)) {
    for (const story of stories) {
      if (!isStoryActive(story, nowMs)) continue
      const created = new Date(story.created_at).getTime()
      const expiresAt = created + STORY_WINDOW_MS
      if (soonest == null || expiresAt < soonest) {
        soonest = expiresAt
      }
    }
  }

  return soonest
}

export function removeStoryFromStoriesByUser(
  storiesByUser: StoriesByUserMap,
  userId: string,
  storyId: string
): StoriesByUserMap {
  const uid = String(userId)
  const existing = storiesByUser[uid]
  if (!existing?.length) return storiesByUser

  const filtered = existing.filter((story) => String(story.id) !== String(storyId))
  if (filtered.length === existing.length) return storiesByUser

  const next = { ...storiesByUser }
  if (filtered.length === 0) {
    delete next[uid]
  } else {
    next[uid] = filtered
  }
  return next
}

export async function deleteStoryById(
  client: SupabaseClient,
  storyId: string
): Promise<{ error: PostgrestError | null }> {
  const trimmed = String(storyId ?? "").trim()
  if (!trimmed) {
    return { error: null }
  }

  if (isDemoModeActive()) {
    return { error: null }
  }

  const { error } = await client.from("stories").delete().eq("id", trimmed)
  return { error }
}

export async function fetchActiveStoriesForUserIds(
  client: SupabaseClient,
  userIds: string[]
): Promise<{
  storiesByUser: StoriesByUserMap
  error: PostgrestError | null
}> {
  const ids = [...new Set(userIds.map((id) => String(id).trim()).filter(Boolean))]

  if (ids.length === 0) {
    return { storiesByUser: {}, error: null }
  }

  if (isDemoModeActive()) {
    const active = filterActiveStories(getDemoStoriesForUserIds(ids))
    return { storiesByUser: groupActiveStoriesByUser(active), error: null }
  }

  const { data, error } = await client
    .from("stories")
    .select(ACTIVE_STORIES_SELECT)
    .in("user_id", ids)
    .order("created_at", { ascending: false })

  if (error) {
    return { storiesByUser: {}, error }
  }

  const active = filterActiveStories((data ?? []) as ActiveStoryRow[])
  return { storiesByUser: groupActiveStoriesByUser(active), error: null }
}

export type StoryBarProfile = {
  id: string
  username?: string | null
  avatar_url?: string | null
}

/** Load following-feed story bar data (same query + expiration as profile). */
export async function fetchFollowingStoriesBarData(
  client: SupabaseClient,
  viewerUserId: string,
  viewerProfile: StoryBarProfile | null
): Promise<{
  storiesByUser: StoriesByUserMap
  users: StoryBarProfile[]
  currentUserProfile: StoryBarProfile
  error: PostgrestError | null
}> {
  const currentUserProfile: StoryBarProfile = viewerProfile
    ? {
        id: viewerProfile.id,
        username: viewerProfile.username,
        avatar_url: viewerProfile.avatar_url,
      }
    : { id: viewerUserId, username: null, avatar_url: null }

  if (isDemoModeActive()) {
    const followingIds = getDemoFollowingIds(viewerUserId)
    const storyUserIds = [...new Set([...followingIds, viewerUserId])]
    const { storiesByUser } = await fetchActiveStoriesForUserIds(
      client,
      storyUserIds
    )
    const userIdsWithStories = Object.keys(storiesByUser)
    const users = getDemoStoryBarProfiles(userIdsWithStories)
    const latestStoryMs = (id: string) =>
      new Date(storiesByUser[id][0].created_at).getTime()
    users.sort((a, b) => latestStoryMs(b.id) - latestStoryMs(a.id))

    return {
      storiesByUser,
      users,
      currentUserProfile,
      error: null,
    }
  }

  const { data: following, error: followingErr } = await client
    .from("followers")
    .select("following_id")
    .eq("follower_id", viewerUserId)

  if (followingErr) {
    return {
      storiesByUser: {},
      users: [],
      currentUserProfile,
      error: followingErr,
    }
  }

  const followingIds = [
    ...new Set(
      (following ?? [])
        .map((row) => row.following_id)
        .filter((id): id is string => id != null && String(id).trim() !== "")
    ),
  ]

  const storyUserIds = [...new Set([...followingIds, viewerUserId])]
  const { storiesByUser, error: storiesErr } =
    await fetchActiveStoriesForUserIds(client, storyUserIds)

  if (storiesErr) {
    return {
      storiesByUser: {},
      users: [],
      currentUserProfile,
      error: storiesErr,
    }
  }

  const userIdsWithStories = Object.keys(storiesByUser)
  if (userIdsWithStories.length === 0) {
    return {
      storiesByUser,
      users: [],
      currentUserProfile,
      error: null,
    }
  }

  const { data: profiles, error: profilesErr } = await client
    .from("profiles")
    .select("id, username, avatar_url")
    .in("id", userIdsWithStories)

  if (profilesErr) {
    return {
      storiesByUser,
      users: [],
      currentUserProfile,
      error: profilesErr,
    }
  }

  const latestStoryMs = (id: string) =>
    new Date(storiesByUser[id][0].created_at).getTime()

  const users = [...(profiles ?? [])] as StoryBarProfile[]
  users.sort((a, b) => latestStoryMs(b.id) - latestStoryMs(a.id))

  return {
    storiesByUser,
    users,
    currentUserProfile,
    error: null,
  }
}

/** @deprecated Use ACTIVE_STORIES_SELECT */
export const FEED_STORIES_SELECT = ACTIVE_STORIES_SELECT
