import type { SupabaseClient } from "@supabase/supabase-js"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressOptions } from "@/lib/uploadProgress/types"
import { validateImageUpload } from "@/lib/uploadValidation"

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

  const fileName = `${userId}/${Date.now()}-${file.name}`

  report({ percent: 15, stage: "Uploading media…" })

  if (options?.onProgress) {
    const { error: uploadError } = await uploadToSupabaseStorageWithProgress(
      supabase,
      {
        bucket: "stories",
        path: fileName,
        file,
        upsert: true,
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
      return { ok: false, message: uploadError }
    }
  } else {
    const { error: uploadError } = await supabase.storage
      .from("stories")
      .upload(fileName, file, { upsert: true })

    if (uploadError) {
      console.error("[publishStory] upload failed", uploadError)
      return { ok: false, message: uploadError.message }
    }
  }

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) {
    return { ok: false, message: "Missing NEXT_PUBLIC_SUPABASE_URL" }
  }

  const publicUrl = `${base}/storage/v1/object/public/stories/${fileName}`

  report({ percent: 85, stage: "Publishing story…" })

  const { error: insertError } = await supabase.from("stories").insert({
    user_id: userId,
    image_url: publicUrl,
  })

  if (insertError) {
    console.error("[publishStory] insert failed", insertError)
    return { ok: false, message: handleSupabaseError(insertError) }
  }

  report({ percent: 95, stage: "Finishing…" })
  return { ok: true }
}
