import type { SupabaseClient } from "@supabase/supabase-js"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressOptions } from "@/lib/uploadProgress/types"
import { validateImageUpload } from "@/lib/uploadValidation"
import { IMMUTABLE_MEDIA_CACHE_CONTROL } from "@/lib/storageCacheControl"
import { prepareImageForUpload } from "@/lib/imagePreparation"
import { optimizedStorageObjectPath } from "@/lib/storageOptimizedMedia"

export async function publishStory(
  supabase: SupabaseClient,
  userId: string,
  file: File,
  options?: UploadProgressOptions
): Promise<{ ok: true } | { ok: false; message: string }> {
  const report = createMonotonicReporter(options?.onProgress)

  if (!userId || !file) {
    return { ok: false, message: "Missing story image" }
  }

  report({ percent: 8, stage: "Preparing story…" })

  const validationError = validateImageUpload(file)
  if (validationError) {
    return { ok: false, message: validationError }
  }

  let uploadFile: File
  try {
    uploadFile = await prepareImageForUpload("story", file)
  } catch (error) {
    return {
      ok: false,
      message:
        error instanceof Error ? error.message : "Couldn't prepare that story image.",
    }
  }

  const fileName = optimizedStorageObjectPath(userId, "jpg")

  report({ percent: 15, stage: "Uploading media…" })

  if (options?.onProgress) {
    const { error: uploadError } = await uploadToSupabaseStorageWithProgress(
      supabase,
      {
        bucket: "stories",
        path: fileName,
        file: uploadFile,
        upsert: true,
        cacheControl: IMMUTABLE_MEDIA_CACHE_CONTROL,
        onProgress: (loaded, total) => {
          report({
            percent: mapUploadBytesToPercent(loaded, total, {
              start: 18,
              end: 78,
            }),
            stage: "Uploading media…",
          })
        },
      }
    )
    if (uploadError) {
      console.error("[publishStory] upload failed", uploadError)
      return {
        ok: false,
        message: toUserFacingErrorMessage(
          typeof uploadError === "string" ? uploadError : { message: uploadError }
        ),
      }
    }
  } else {
    const { error: uploadError } = await supabase.storage
      .from("stories")
      .upload(fileName, uploadFile, {
        upsert: true,
        cacheControl: IMMUTABLE_MEDIA_CACHE_CONTROL,
      })

    if (uploadError) {
      console.error("[publishStory] upload failed", uploadError)
      return { ok: false, message: toUserFacingErrorMessage(uploadError) }
    }
  }

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) {
    console.error("[publishStory] NEXT_PUBLIC_SUPABASE_URL is not set")
    return {
      ok: false,
      message: "Story couldn't be published. Please try again.",
    }
  }

  const publicUrl = `${base}/storage/v1/object/public/stories/${fileName}`

  report({ percent: 85, stage: "Publishing story…" })

  const { error: insertError } = await supabase.from("stories").insert({
    user_id: userId,
    image_url: publicUrl,
  })

  if (insertError) {
    console.error("[publishStory] insert failed", insertError)
    return { ok: false, message: toUserFacingErrorMessage(insertError) }
  }

  report({ percent: 95, stage: "Finishing…" })
  return { ok: true }
}
