import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"
import type { FeedStoryPreviewV1 } from "@/lib/backendV2/contracts"
import {
  getStoryViewerSessionSeen,
  isStoryViewedInSession,
  markStoryViewedInSession,
} from "@/lib/storyViewerSession"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { purgeStoryStorageAfterStoryRemoval } from "@/lib/storyStorageAfterDelete"
import {
  getDemoFollowingIds,
  getDemoStoriesForUserIds,
  getDemoStoryBarProfiles,
} from "@/lib/demo/demoFeed"

/** Stories remain visible for 24 hours (matches feed + profile). */
export const STORY_WINDOW_MS = 24 * 60 * 60 * 1000

export const ACTIVE_STORIES_SELECT =
  "id, user_id, image_url, storage_path, created_at, text_overlays"

export type StoryTextOverlay = {
  id?: string
  text?: string
  x?: number
  y?: number
  scale?: number
  rotation?: number
  red?: number
  green?: number
  blue?: number
  alpha?: number
  alignment?: string
  background?: boolean
}

export type ActiveStoryRow = {
  id: string
  user_id: string
  image_url: string
  created_at: string
  text_overlays?: StoryTextOverlay[] | null
  /** Durable per-viewer flag from `story_views` (optional on older payloads). */
  viewer_has_seen?: boolean
}

const STORY_VIDEO_EXTENSION = /\.(mp4|mov|m4v|webm)$/i

/** iOS stores video stories in image_url. An <img> of that URL renders blank. */
export function storyMediaIsVideo(url: string | null | undefined): boolean {
  const path = String(url ?? "").split("?")[0]?.split("#")[0] ?? ""
  return STORY_VIDEO_EXTENSION.test(path)
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

export function activeStoryCreatedAfterISO(nowMs = Date.now()): string {
  return new Date(nowMs - STORY_WINDOW_MS).toISOString()
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

  const { data: existing, error: readError } = await client
    .from("stories")
    .select("image_url")
    .eq("id", trimmed)
    .maybeSingle()
  if (readError) return { error: readError }

  const { error } = await client.from("stories").delete().eq("id", trimmed)
  if (error) return { error }

  const imageURL = (existing as { image_url?: string | null } | null)?.image_url
  if (imageURL) {
    try {
      await purgeStoryStorageAfterStoryRemoval(client, imageURL)
    } catch (storageError) {
      console.warn("[deleteStoryById] storage cleanup:", storageError)
    }
  }
  return { error: null }
}

export function feedStoryPreviewsToActiveRows(
  previews: FeedStoryPreviewV1[]
): ActiveStoryRow[] {
  return previews.map((s) => ({
    id: String(s.id),
    user_id: String(s.user_id),
    image_url: String(s.image_url),
    created_at: String(s.created_at),
    viewer_has_seen: s.viewer_has_seen === true,
  }))
}

export function storyViewerHasSeen(
  story: Pick<ActiveStoryRow, "id" | "viewer_has_seen">
): boolean {
  return story.viewer_has_seen === true || isStoryViewedInSession(story.id)
}

/** Oldest unviewed slide index in newest-first per-user arrays (viewer parity with native). */
export function preferredStoryEntryIndex(stories: ActiveStoryRow[]): number {
  if (!stories.length) return 0
  const chronological = [...stories].sort(
    (a, b) =>
      new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  )
  const session = getStoryViewerSessionSeen()
  const hasViewed = (s: ActiveStoryRow) =>
    s.viewer_has_seen === true || session.has(String(s.id))
  const target =
    chronological.find((s) => !hasViewed(s)) ?? chronological[0]
  const idx = stories.findIndex((s) => String(s.id) === String(target?.id))
  return idx >= 0 ? idx : 0
}

export function markStoryViewedInStoriesByUser(
  storiesByUser: StoriesByUserMap,
  userId: string,
  storyId: string
): StoriesByUserMap {
  const uid = String(userId)
  const list = storiesByUser[uid]
  if (!list?.length) return storiesByUser
  let changed = false
  const nextList = list.map((story) => {
    if (String(story.id) !== String(storyId)) return story
    if (story.viewer_has_seen === true) return story
    changed = true
    return { ...story, viewer_has_seen: true }
  })
  if (!changed) return storiesByUser
  return { ...storiesByUser, [uid]: nextList }
}

export async function recordStoryView(
  client: SupabaseClient,
  storyId: string
): Promise<void> {
  const id = String(storyId ?? "").trim()
  if (!id || isDemoModeActive()) return
  markStoryViewedInSession(id)
  const { error } = await client.rpc("rpc_v1_story_record_view", {
    p_story_id: id,
  })
  if (error) {
    console.warn("[recordStoryView]", error.message)
  }
}

export async function fetchViewerActiveStoriesFromRpc(
  client: SupabaseClient
): Promise<{
  stories: ActiveStoryRow[]
  error: PostgrestError | null
}> {
  const { data, error } = await client.rpc("rpc_v1_viewer_active_stories")
  if (error) {
    return { stories: [], error }
  }
  const rows = (Array.isArray(data) ? data : []) as ActiveStoryRow[]
  return { stories: filterActiveStories(rows), error: null }
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

  const {
    data: { session },
  } = await client.auth.getSession()
  if (session) {
    const { stories: rpcStories, error: rpcError } =
      await fetchViewerActiveStoriesFromRpc(client)
    if (!rpcError) {
      const idSet = new Set(ids)
      const scoped = rpcStories.filter((s) => idSet.has(String(s.user_id)))
      return {
        storiesByUser: groupActiveStoriesByUser(scoped),
        error: null,
      }
    }
  }

  const { data, error } = await client
    .from("stories")
    .select(ACTIVE_STORIES_SELECT)
    .in("user_id", ids)
    .gt("created_at", activeStoryCreatedAfterISO())
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
