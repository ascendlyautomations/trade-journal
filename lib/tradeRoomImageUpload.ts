import type { SupabaseClient } from "@supabase/supabase-js"
import { prepareImageForUpload } from "@/lib/imagePreparation"
import {
  optimizedStorageObjectPath,
} from "@/lib/storageOptimizedMedia"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressReporter } from "@/lib/uploadProgress/types"

export async function uploadTradeRoomImage(
  supabase: SupabaseClient,
  userId: string,
  file: File,
  report?: UploadProgressReporter
): Promise<string> {
  report?.({ percent: 10, stage: "Processing…" })
  const uploadFile = await prepareImageForUpload("room", file)
  void userId
  const filePath = optimizedStorageObjectPath("room-images", "jpg")
  const mediaReport = report
    ? createMonotonicReporter(report, { min: 18, max: 85 })
    : undefined

  const { error: upErr } = await uploadToSupabaseStorageWithProgress(supabase, {
    bucket: "avatars",
    path: filePath,
    file: uploadFile,
    upsert: true,
    onProgress: mediaReport
      ? (loaded, total) => {
          mediaReport({
            percent: mapUploadBytesToPercent(loaded, total, { start: 20, end: 85 }),
            stage: "Uploading…",
          })
        }
      : undefined,
  })

  if (upErr) throw new Error(upErr)

  const { data: urlData } = supabase.storage.from("avatars").getPublicUrl(filePath)
  report?.({ percent: 95, stage: "Done" })
  return urlData.publicUrl
}
