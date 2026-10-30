import type { SupabaseClient } from "@supabase/supabase-js"
import { IMMUTABLE_MEDIA_CACHE_CONTROL } from "@/lib/storageCacheControl"
import {
  profilePostStorageObjectPath,
} from "@/lib/storageOptimizedMedia"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressReporter } from "@/lib/uploadProgress/types"
import { buildRoomSharePostInsert, type PendingRoomShareDraft } from "@/lib/roomSharePost"
import { insertProfileWallPostIdempotent } from "@/lib/insertProfileWallPostIdempotent"

export type PublishProfilePostCheckpoint = {
  clientPublishId: string
  imageStoragePath: string | null
}

export type PublishProfilePostInput = {
  userId: string
  text: string
  imageFile: File | null
  pendingRoomShare: PendingRoomShareDraft | null
}

export type PublishProfilePostResult =
  | { ok: true; post: Record<string, unknown>; checkpoint: PublishProfilePostCheckpoint }
  | { ok: false; message: string; checkpoint: PublishProfilePostCheckpoint }

function newPublishCheckpoint(): PublishProfilePostCheckpoint {
  return {
    clientPublishId: crypto.randomUUID(),
    imageStoragePath: null,
  }
}

export async function publishProfilePost(
  supabase: SupabaseClient,
  input: PublishProfilePostInput,
  report: UploadProgressReporter,
  checkpoint?: PublishProfilePostCheckpoint | null
): Promise<PublishProfilePostResult> {
  const { userId, text, imageFile, pendingRoomShare } = input
  const snapshotText = text.trim()
  const session = checkpoint ?? newPublishCheckpoint()

  if (!snapshotText && !imageFile && !pendingRoomShare) {
    return {
      ok: false,
      message: "Add some text, an image, or a room share.",
      checkpoint: session,
    }
  }

  let imageUrl: string | null = null

  if (imageFile) {
    report({ percent: 10, stage: "Processing image…" })
    const fileName =
      session.imageStoragePath ??
      profilePostStorageObjectPath(userId, session.clientPublishId, "jpg")
    session.imageStoragePath = fileName

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
        upsert: true,
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
      return { ok: false, message: upErr, checkpoint: session }
    }

    const base = process.env.NEXT_PUBLIC_SUPABASE_URL
    imageUrl = base
      ? `${base}/storage/v1/object/public/profile_posts/${fileName}`
      : null
  } else {
    report({ percent: 40, stage: "Creating post…" })
  }

  const baseInsert = pendingRoomShare
    ? buildRoomSharePostInsert(userId, pendingRoomShare, snapshotText, imageUrl)
    : {
        user_id: userId,
        content: snapshotText || null,
        image_url: imageUrl,
      }

  const insertPayload = {
    ...baseInsert,
    client_publish_id: session.clientPublishId,
  }

  report({ percent: 82, stage: "Publishing…" })

  const inserted = await insertProfileWallPostIdempotent(supabase, insertPayload)
  if (!inserted.ok) {
    return { ok: false, message: inserted.message, checkpoint: session }
  }

  report({ percent: 95, stage: "Finishing…" })
  return { ok: true, post: inserted.post, checkpoint: session }
}
