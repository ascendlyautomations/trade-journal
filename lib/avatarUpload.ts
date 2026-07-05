import { compressImage } from "./compressImage"
import { supabase } from "./supabaseClient"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressOptions } from "@/lib/uploadProgress/types"
import { validateImageUpload } from "./uploadValidation"

/** Upload to public `avatars` bucket; returns public URL or null on failure. */
export async function uploadAvatarFile(
  userId: string,
  file: File,
  options?: UploadProgressOptions
): Promise<string | null> {
  const validationError = validateImageUpload(file)
  if (validationError) {
    console.error("Avatar upload validation:", validationError)
    return null
  }

  let uploadFile: File = file
  if (file.type?.startsWith("image/")) {
    uploadFile = await compressImage(file)
  }
  const fileName = `${userId}/${Date.now()}-${uploadFile.name}`
  const report = createMonotonicReporter(options?.onProgress)

  if (options?.onProgress) {
    report({ percent: 10, stage: "Processing…" })
    const { error } = await uploadToSupabaseStorageWithProgress(supabase, {
      bucket: "avatars",
      path: fileName,
      file: uploadFile,
      upsert: true,
      onProgress: (loaded, total) => {
        report({
          percent: mapUploadBytesToPercent(loaded, total, {
            start: 15,
            end: 92,
          }),
          stage: "Uploading…",
        })
      },
    })
    if (error) {
      console.error("Avatar upload error:", error)
      return null
    }
  } else {
    const { error } = await supabase.storage
      .from("avatars")
      .upload(fileName, uploadFile, { upsert: true })

    if (error) {
      console.error("Avatar upload error:", error.message)
      return null
    }
  }

  report({ percent: 96, stage: "Saving…" })
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  return `${base}/storage/v1/object/public/avatars/${fileName}`
}
