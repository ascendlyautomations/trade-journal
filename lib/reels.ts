import type { SupabaseClient } from "@supabase/supabase-js"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import {
  captureReelVideoThumbnail,
  uploadReelThumbnailBlob,
  uploadReelVideoFile,
  validateReelVideoFile,
} from "@/lib/reelVideo"

export type ReelVisibility = "public" | "private"

export type ReelRow = {
  id: string
  user_id: string
  caption: string | null
  video_url: string
  thumbnail_url: string
  duration_seconds: number | null
  visibility: ReelVisibility
  created_at: string
  updated_at: string
}

export const PROFILE_REELS_SELECT =
  "id, user_id, caption, video_url, thumbnail_url, duration_seconds, visibility, created_at, updated_at"

export type PublishReelInput = {
  userId: string
  file: File
  caption?: string | null
  visibility?: ReelVisibility
}

export async function publishReel(
  supabase: SupabaseClient,
  input: PublishReelInput
): Promise<{ reel: ReelRow } | { error: string }> {
  const validationError = validateReelVideoFile(input.file)
  if (validationError) {
    return { error: validationError.message }
  }

  let thumbnailBlob: Blob
  let durationSeconds: number

  try {
    const captured = await captureReelVideoThumbnail(input.file)
    thumbnailBlob = captured.blob
    durationSeconds = captured.metadata.durationSeconds
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Could not process this video."
    return { error: message }
  }

  const videoUpload = await uploadReelVideoFile(
    supabase,
    input.userId,
    input.file
  )
  if ("error" in videoUpload) {
    return { error: videoUpload.error }
  }

  const thumbUpload = await uploadReelThumbnailBlob(
    supabase,
    input.userId,
    thumbnailBlob
  )
  if ("error" in thumbUpload) {
    return { error: thumbUpload.error }
  }

  const caption = input.caption?.trim() ?? ""

  const { data, error } = await supabase
    .from("reels")
    .insert({
      user_id: input.userId,
      caption: caption || null,
      video_url: videoUpload.publicUrl,
      thumbnail_url: thumbUpload.publicUrl,
      duration_seconds: durationSeconds,
      visibility: input.visibility ?? "public",
    })
    .select(PROFILE_REELS_SELECT)
    .single()

  if (error) {
    return { error: handleSupabaseError(error) }
  }

  return { reel: data as ReelRow }
}

export type UpdateReelCaptionInput = {
  reelId: string
  userId: string
  caption?: string | null
}

/** Update reel metadata (caption only in phase 1). Owner-only via RLS. */
export async function updateReelCaption(
  supabase: SupabaseClient,
  input: UpdateReelCaptionInput
): Promise<{ reel: ReelRow } | { error: string }> {
  const caption = input.caption?.trim() ?? ""

  const { data, error } = await supabase
    .from("reels")
    .update({ caption: caption || null })
    .eq("id", input.reelId)
    .eq("user_id", input.userId)
    .select(PROFILE_REELS_SELECT)
    .single()

  if (error) {
    return { error: handleSupabaseError(error) }
  }

  return { reel: data as ReelRow }
}

export async function deleteReel(
  supabase: SupabaseClient,
  input: { reelId: string; userId: string }
): Promise<{ ok: true } | { error: string }> {
  const { error } = await supabase
    .from("reels")
    .delete()
    .eq("id", input.reelId)
    .eq("user_id", input.userId)

  if (error) {
    return { error: handleSupabaseError(error) }
  }

  return { ok: true }
}
