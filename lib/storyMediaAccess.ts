import type { SupabaseClient } from "@supabase/supabase-js"
import { createStorySignedMediaUrl } from "@/lib/storySignedMedia"

export type StoryDmMediaAccess = {
  allowed: boolean
  reason: string
  id?: string
  user_id?: string
  created_at?: string
  storage_path?: string | null
  image_url?: string | null
}

export async function fetchStoryDmMediaAccess(
  client: SupabaseClient,
  storyId: string
): Promise<StoryDmMediaAccess> {
  const trimmed = storyId.trim()
  if (!trimmed) {
    return { allowed: false, reason: "invalid" }
  }

  const { data, error } = await client.rpc("rpc_v1_story_dm_media_access", {
    p_story_id: trimmed,
  })

  if (error || !data || typeof data !== "object") {
    return { allowed: false, reason: "error" }
  }

  const row = data as Record<string, unknown>
  return {
    allowed: row.allowed === true,
    reason: String(row.reason ?? "unavailable"),
    id: typeof row.id === "string" ? row.id : undefined,
    user_id: typeof row.user_id === "string" ? row.user_id : undefined,
    created_at: typeof row.created_at === "string" ? row.created_at : undefined,
    storage_path:
      typeof row.storage_path === "string" ? row.storage_path : null,
    image_url: typeof row.image_url === "string" ? row.image_url : null,
  }
}

export async function resolveStoryPlaybackUrl(
  client: SupabaseClient,
  access: StoryDmMediaAccess
): Promise<string | null> {
  if (!access.allowed) return null
  return createStorySignedMediaUrl(client, {
    storage_path: access.storage_path,
    image_url: access.image_url,
  })
}

export type ArchivedStoryRow = {
  id: string
  user_id: string
  image_url: string | null
  storage_path: string | null
  resolved_storage_path: string | null
  created_at: string
  text_overlays?: unknown
}

export async function fetchOwnerStoryArchive(
  client: SupabaseClient,
  limit = 60,
  offset = 0
): Promise<ArchivedStoryRow[]> {
  const { data, error } = await client.rpc("rpc_v1_owner_story_archive", {
    p_limit: limit,
    p_offset: offset,
  })
  if (error || !data || typeof data !== "object") return []
  const stories = (data as { stories?: unknown }).stories
  if (!Array.isArray(stories)) return []
  return stories.filter(
    (row): row is ArchivedStoryRow =>
      row != null &&
      typeof row === "object" &&
      typeof (row as ArchivedStoryRow).id === "string"
  )
}

export async function fetchStoryForViewer(
  client: SupabaseClient,
  storyId: string
): Promise<ArchivedStoryRow | null> {
  const trimmed = storyId.trim()
  if (!trimmed) return null
  const { data, error } = await client.rpc("rpc_v1_story_for_viewer", {
    p_story_id: trimmed,
  })
  if (error) {
    console.info(
      `[StoryDebug] rpc_v1_story_for_viewer error story=${trimmed} message=${error.message}`
    )
    return null
  }
  if (!data || typeof data !== "object") {
    console.info(`[StoryDebug] rpc_v1_story_for_viewer null story=${trimmed}`)
    return null
  }
  const row = data as ArchivedStoryRow
  if (typeof row.id !== "string") {
    console.info(`[StoryDebug] rpc_v1_story_for_viewer invalid story=${trimmed}`)
    return null
  }
  console.info(
    `[StoryDebug] rpc_v1_story_for_viewer ok story=${row.id} storage_path=${row.storage_path ?? "nil"} resolved=${row.resolved_storage_path ?? "nil"} image_url=${row.image_url ?? "nil"}`
  )
  return row
}