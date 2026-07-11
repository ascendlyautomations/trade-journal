import type { SupabaseClient } from "@supabase/supabase-js"
import type { ImageCropPresetId } from "./imageCropPresets"
import { compressScreenshot } from "./compressImage"
import { uploadToSupabaseStorageWithProgress } from "./supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "./uploadProgress/reportProgress"
import type { UploadProgressReporter } from "./uploadProgress/types"
import { validateImageUpload } from "./uploadValidation"
import { toUserFacingErrorMessage, USER_FACING_ERROR_MESSAGES } from "./userFacingError"

/** Shared crop preset for trades, posts, achievements, and other content images. */
export const CONTENT_IMAGE_CROP_PRESET: ImageCropPresetId = "content"

/** Storage transform preset used when rendering content images in cards and modals. */
export const CONTENT_IMAGE_DISPLAY_PRESET = "feed-thumb" as const

/** Post-crop compression — identical for trades, achievements, and other content uploads. */
export async function compressContentImage(file: File): Promise<File> {
  return compressScreenshot(file)
}

export type ContentImageUploadOptions = {
  onProgress?: UploadProgressReporter
  processingPercent?: number
  uploadingPercent?: number
  uploadProgressRange?: { start: number; end: number }
}

/** Validate, compress, and upload a content image to the screenshots bucket. */
export async function uploadContentImageToStorage(
  client: SupabaseClient,
  userId: string,
  file: File,
  options?: ContentImageUploadOptions
): Promise<{ path: string | null; error: string | null }> {
  const validationError = validateImageUpload(file)
  if (validationError) {
    return { path: null, error: validationError }
  }

  const report = options?.onProgress
    ? createMonotonicReporter(options.onProgress, { min: 10, max: 65 })
    : null

  report?.({
    percent: options?.processingPercent ?? 10,
    stage: "Processing image…",
  })

  let uploadFile: File = file
  if (file.type?.startsWith("image/")) {
    uploadFile = await compressContentImage(file)
  }
  const fileName = `${userId}/${Date.now()}-${uploadFile.name}`

  report?.({
    percent: options?.uploadingPercent ?? 18,
    stage: "Uploading media…",
  })

  const uploadRange = options?.uploadProgressRange ?? { start: 20, end: 65 }

  if (report) {
    const { error: upErr } = await uploadToSupabaseStorageWithProgress(client, {
      bucket: "screenshots",
      path: fileName,
      file: uploadFile,
      contentType: uploadFile.type || "image/jpeg",
      onProgress: (loaded, total) => {
        report({
          percent: mapUploadBytesToPercent(loaded, total, uploadRange),
          stage: "Uploading media…",
        })
      },
    })
    if (upErr) {
      console.error("[uploadContentImage] upload error:", upErr)
      return {
        path: null,
        error: toUserFacingErrorMessage(
          upErr,
          USER_FACING_ERROR_MESSAGES.TRADE_IMAGE_UPLOAD_FAILED
        ),
      }
    }
  } else {
    const { error: upErr } = await client.storage
      .from("screenshots")
      .upload(fileName, uploadFile)
    if (upErr) {
      console.error("[uploadContentImage] upload error:", upErr)
      return {
        path: null,
        error: toUserFacingErrorMessage(
          upErr,
          USER_FACING_ERROR_MESSAGES.TRADE_IMAGE_UPLOAD_FAILED
        ),
      }
    }
  }

  return { path: fileName, error: null }
}
