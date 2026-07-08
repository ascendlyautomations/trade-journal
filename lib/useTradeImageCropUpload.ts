"use client"

import { CONTENT_IMAGE_CROP_PRESET } from "./contentImagePipeline"
import {
  useImageCropUpload,
  type UseImageCropUploadResult,
} from "./useImageCropUpload"

type UseTradeImageCropUploadOptions = {
  onCropped: (file: File) => void
  onValidationError: (message: string) => void
}

/** Crop hook configured for trade screenshot uploads (Input Trade + Quick Trade). */
export function useTradeImageCropUpload(
  options: UseTradeImageCropUploadOptions
): UseImageCropUploadResult {
  return useImageCropUpload({
    preset: CONTENT_IMAGE_CROP_PRESET,
    onCropped: options.onCropped,
    onValidationError: options.onValidationError,
  })
}
