import type { TradeScreenshotDisplayMode } from "./tradeScreenshotDisplay"
import { CONTENT_IMAGE_CROP_PRESET } from "./contentImagePipeline"
import { fillFrameSize, getImageCropPreset } from "./imageCropPresets"
import {
  DEFAULT_ZOOM_PAN_TRANSFORM,
  renderZoomPanCrop,
} from "./renderImageCrop"
import { computeCoverZoom } from "./zoomPanCrop"

export type { TradeScreenshotDisplayMode } from "./tradeScreenshotDisplay"

async function loadImageSize(
  file: File
): Promise<{ width: number; height: number }> {
  const objectUrl = URL.createObjectURL(file)
  try {
    const image = await new Promise<HTMLImageElement>((resolve, reject) => {
      const img = new Image()
      img.onload = () => resolve(img)
      img.onerror = () => reject(new Error("Could not load image."))
      img.src = objectUrl
    })
    return { width: image.naturalWidth, height: image.naturalHeight }
  } finally {
    URL.revokeObjectURL(objectUrl)
  }
}

/** Re-export a trade screenshot at Fit (letterbox) or Fill (cover) for the content frame. */
export async function renderTradeScreenshotDisplayMode(
  file: File,
  mode: TradeScreenshotDisplayMode
): Promise<File> {
  const preset = getImageCropPreset(CONTENT_IMAGE_CROP_PRESET)
  if (mode === "fit") {
    return renderZoomPanCrop(file, preset, DEFAULT_ZOOM_PAN_TRANSFORM)
  }

  const frame = fillFrameSize(preset)
  const size = await loadImageSize(file)
  const zoom = computeCoverZoom(
    size.width,
    size.height,
    frame.width,
    frame.height,
    preset.maxZoom
  )
  return renderZoomPanCrop(file, preset, { zoom, offset: { x: 0, y: 0 } })
}

/** Load a remote or absolute screenshot URL as a File for crop / Fit–Fill re-export. */
export async function fetchImageUrlAsFile(
  url: string,
  fileName = "screenshot.jpg"
): Promise<File> {
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error("Could not load screenshot.")
  }
  const blob = await response.blob()
  const type = blob.type && blob.type.startsWith("image/") ? blob.type : "image/jpeg"
  return new File([blob], fileName, { type })
}
