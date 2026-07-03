import type { SupabaseClient } from "@supabase/supabase-js"
import { deleteReelStorageFiles } from "@/lib/reels"

const USER_FOLDER_BUCKETS = [
  "avatars",
  "screenshots",
  "stories",
  "reels",
  "profile_posts",
  "csv-support",
] as const

function publicUrlToStoragePath(
  bucket: string,
  url: string | null | undefined
): string | null {
  if (!url?.trim()) return null
  const marker = `/storage/v1/object/public/${bucket}/`
  const idx = url.indexOf(marker)
  if (idx < 0) return null
  return decodeURIComponent(url.slice(idx + marker.length))
}

async function listAllObjectPaths(
  supabase: SupabaseClient,
  bucket: string,
  prefix: string
): Promise<string[]> {
  const paths: string[] = []
  const queue = [prefix.replace(/^\/+|\/+$/g, "")]

  while (queue.length > 0) {
    const folder = queue.shift()
    if (!folder) continue

    const { data, error } = await supabase.storage.from(bucket).list(folder, {
      limit: 1000,
    })

    if (error) {
      console.warn(`[deleteUserStorage] list ${bucket}/${folder}:`, error.message)
      continue
    }

    for (const entry of data ?? []) {
      const fullPath = `${folder}/${entry.name}`.replace(/\/+/g, "/")
      if (entry.id == null) {
        queue.push(fullPath)
        continue
      }
      paths.push(fullPath)
    }
  }

  return paths
}

async function removeStoragePaths(
  supabase: SupabaseClient,
  bucket: string,
  paths: string[]
) {
  if (paths.length === 0) return

  const chunkSize = 100
  for (let i = 0; i < paths.length; i += chunkSize) {
    const chunk = paths.slice(i, i + chunkSize)
    const { error } = await supabase.storage.from(bucket).remove(chunk)
    if (error) {
      console.warn(`[deleteUserStorage] remove ${bucket}:`, error.message)
    }
  }
}

/** Best-effort removal of all storage objects owned by the user. */
export async function deleteUserStorageFiles(
  supabase: SupabaseClient,
  userId: string
): Promise<void> {
  const userPrefix = userId.trim()
  if (!userPrefix) return

  for (const bucket of USER_FOLDER_BUCKETS) {
    const paths = await listAllObjectPaths(supabase, bucket, userPrefix)
    await removeStoragePaths(supabase, bucket, paths)
  }

  const { data: reels, error: reelsError } = await supabase
    .from("reels")
    .select("video_url, thumbnail_url")
    .eq("user_id", userId)

  if (reelsError) {
    console.warn("[deleteUserStorage] reels lookup:", reelsError.message)
  } else {
    for (const reel of reels ?? []) {
      await deleteReelStorageFiles(supabase, reel)
    }
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("avatar_url")
    .eq("id", userId)
    .maybeSingle()

  if (profileError) {
    console.warn("[deleteUserStorage] profile avatar lookup:", profileError.message)
  } else {
    const avatarPath = publicUrlToStoragePath("avatars", profile?.avatar_url)
    if (avatarPath) {
      await removeStoragePaths(supabase, "avatars", [avatarPath])
    }
  }

  const { data: trades, error: tradesError } = await supabase
    .from("trades")
    .select("image_url")
    .eq("user_id", userId)

  if (tradesError) {
    console.warn("[deleteUserStorage] trade screenshots lookup:", tradesError.message)
  } else {
    const tradePaths = (trades ?? [])
      .map((row) => publicUrlToStoragePath("screenshots", row.image_url))
      .filter((path): path is string => Boolean(path))
    await removeStoragePaths(supabase, "screenshots", tradePaths)
  }
}
