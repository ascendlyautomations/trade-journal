import type { SupabaseClient } from "@supabase/supabase-js"
import { IMMUTABLE_MEDIA_CACHE_CONTROL } from "@/lib/storageCacheControl"
import { optimizedStorageObjectPath } from "@/lib/storageOptimizedMedia"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressReporter } from "@/lib/uploadProgress/types"
import { buildRoomSharePostInsert, type PendingRoomShareDraft } from "@/lib/roomSharePost"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { PROFILE_WALL_POST_SELECT } from "@/lib/profileWallPosts"

export type PublishProfilePostInput = {
  userId: string
  text: string
  imageFile: File | null
  pendingRoomShare: PendingRoomShareDraft | null
}

export type PublishProfilePostResult =
  | { ok: true; post: Record<string, unknown> }
  | { ok: false; message: string }

export async function publishProfilePost(
  supabase: SupabaseClient,
  input: PublishProfilePostInput,
  report: UploadProgressReporter
): Promise<PublishProfilePostResult> {
  const { userId, text, imageFile, pendingRoomShare } = input
  const snapshotText = text.trim()

  if (!snapshotText && !imageFile && !pendingRoomShare) {
    return { ok: false, message: "Add some text, an image, or a room share." }
  }

  let imageUrl: string | null = null

  if (imageFile) {
    report({ percent: 10, stage: "Processing image…" })
    const fileName = optimizedStorageObjectPath(userId, "jpg")

    report({ percent: 18, stage: "Uploading media…" })
    const mediaReport = createMonotonicReporter(report, {
      min: 18,
      max: 72,
    })
    const { error: upErr } = await uploadToSupabaseStorageWithProgress(
      supabase,
      {
        bucket: "profile_posts",
        path: fileName,
        file: imageFile,
        upsert: false,
        cacheControl: IMMUTABLE_MEDIA_CACHE_CONTROL,
        onProgress: (loaded, total) => {
          mediaReport({
            percent: mapUploadBytesToPercent(loaded, total, {
              start: 20,
              end: 72,
            }),
            stage: "Uploading media…",
          })
        },
      }
    )

    if (upErr) {
      return { ok: false, message: upErr }
    }

    const base = process.env.NEXT_PUBLIC_SUPABASE_URL
    imageUrl = base
      ? `${base}/storage/v1/object/public/profile_posts/${fileName}`
      : null
  } else {
    report({ percent: 40, stage: "Creating post…" })
  }

  const insertPayload = pendingRoomShare
    ? buildRoomSharePostInsert(userId, pendingRoomShare, snapshotText, imageUrl)
    : {
        user_id: userId,
        content: snapshotText || null,
        image_url: imageUrl,
      }

  report({ percent: 82, stage: "Publishing…" })

  const { data: createdPost, error } = await supabase
    .from("profile_posts")
    .insert(insertPayload)
    .select(PROFILE_WALL_POST_SELECT)
    .single()

  if (error) {
    return { ok: false, message: handleSupabaseError(error) }
  }
  if (!createdPost) {
    return { ok: false, message: "Post insert returned no row" }
  }

  report({ percent: 95, stage: "Finishing…" })
  return { ok: true, post: createdPost as Record<string, unknown> }
}
