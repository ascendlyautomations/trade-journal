import type { ImageCropPresetId } from "./imageCropPresets"
import { compressScreenshot } from "./compressImage"

/** Shared crop preset for trades, posts, achievements, and other content images. */
export const CONTENT_IMAGE_CROP_PRESET: ImageCropPresetId = "content"

/** Storage transform preset used when rendering content images in cards and modals. */
export const CONTENT_IMAGE_DISPLAY_PRESET = "feed-thumb" as const

/** Post-crop compression — identical for trades, achievements, and other content uploads. */
export async function compressContentImage(file: File): Promise<File> {
  return compressScreenshot(file)
}
