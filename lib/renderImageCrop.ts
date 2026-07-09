import type { ImageCropPreset } from "./imageCropPresets"
import { fillFrameSize } from "./imageCropPresets"
import { TRADE_IMAGE_LETTERBOX_COLOR } from "./tradeImageAspect"
import {
  clampZoom,
  clampZoomPanOffset,
  computeFitScale,
  computeZoomPanDrawRect,
  DEFAULT_ZOOM_PAN_TRANSFORM,
  type ZoomPanTransform,
} from "./zoomPanCrop"

/** @deprecated Use ZoomPanTransform */
export type ImageCropMode = "fit" | "fill"
/** @deprecated Use ZoomPanOffset */
export type ImageCropOffset = { x: number; y: number }

export type ImageDrawRect = {
  x: number
  y: number
  width: number
  height: number
}

export {
  clampZoom,
  clampZoomPanOffset,
  computeFitScale,
  computeZoomPanDrawRect,
  DEFAULT_ZOOM_PAN_TRANSFORM,
  ZOOM_PAN_MAX,
  ZOOM_PAN_MIN,
  type ZoomPanTransform,
} from "./zoomPanCrop"

export function computeFitExportSize(
  imageWidth: number,
  imageHeight: number,
  maxWidth: number
): { width: number; height: number } {
  const scale = Math.min(1, maxWidth / imageWidth)
  return {
    width: Math.max(1, Math.round(imageWidth * scale)),
    height: Math.max(1, Math.round(imageHeight * scale)),
  }
}

/** @deprecated Cover-style fill — retained for legacy tests. */
export function computeFillDrawRect(
  imageWidth: number,
  imageHeight: number,
  offset: ImageCropOffset = { x: 0, y: 0 },
  frameWidth: number,
  frameHeight: number
): ImageDrawRect {
  const scale = Math.max(frameWidth / imageWidth, frameHeight / imageHeight)
  const width = imageWidth * scale
  const height = imageHeight * scale
  const baseX = (frameWidth - width) / 2
  const baseY = (frameHeight - height) / 2
  const clamped = clampFillOffset(width, height, offset, frameWidth, frameHeight)

  return {
    x: baseX + clamped.x,
    y: baseY + clamped.y,
    width,
    height,
  }
}

/** @deprecated Cover-style clamp — retained for legacy tests. */
export function clampFillOffset(
  drawWidth: number,
  drawHeight: number,
  offset: ImageCropOffset,
  frameWidth: number,
  frameHeight: number
): ImageCropOffset {
  const minX = frameWidth - drawWidth
  const maxX = 0
  const minY = frameHeight - drawHeight
  const maxY = 0

  return {
    x: Math.min(maxX, Math.max(minX, offset.x)),
    y: Math.min(maxY, Math.max(minY, offset.y)),
  }
}

async function loadImageFromFile(file: File): Promise<HTMLImageElement> {
  const objectUrl = URL.createObjectURL(file)

  try {
    return await new Promise<HTMLImageElement>((resolve, reject) => {
      const image = new Image()
      image.onload = () => resolve(image)
      image.onerror = () => reject(new Error("Could not load image."))
      image.src = objectUrl
    })
  } finally {
    URL.revokeObjectURL(objectUrl)
  }
}

function canvasToFile(canvas: HTMLCanvasElement, fileName: string): Promise<File> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (!blob) {
          reject(new Error("Could not export image."))
          return
        }

        const baseName = fileName.replace(/\.[^/.]+$/, "")
        resolve(
          new File([blob], `${baseName}-cropped.webp`, {
            type: "image/webp",
          })
        )
      },
      "image/webp",
      0.92
    )
  })
}

export async function renderZoomPanCrop(
  file: File,
  preset: ImageCropPreset,
  transform: ZoomPanTransform = DEFAULT_ZOOM_PAN_TRANSFORM
): Promise<File> {
  const image = await loadImageFromFile(file)
  const frame = fillFrameSize(preset)
  const zoom = clampZoom(transform.zoom, preset.maxZoom)
  const offset = clampZoomPanOffset(
    image.naturalWidth,
    image.naturalHeight,
    frame.width,
    frame.height,
    zoom,
    transform.offset
  )

  const rect = computeZoomPanDrawRect(
    image.naturalWidth,
    image.naturalHeight,
    frame.width,
    frame.height,
    zoom,
    offset
  )

  const canvas = document.createElement("canvas")
  const ctx = canvas.getContext("2d")
  if (!ctx) {
    throw new Error("Could not prepare image canvas.")
  }

  canvas.width = preset.outputWidth
  canvas.height = preset.outputHeight
  const scaleX = preset.outputWidth / frame.width
  const scaleY = preset.outputHeight / frame.height

  ctx.fillStyle = preset.letterboxColor ?? TRADE_IMAGE_LETTERBOX_COLOR
  ctx.fillRect(0, 0, canvas.width, canvas.height)

  if (preset.mask === "circle") {
    const radius = Math.min(canvas.width, canvas.height) / 2
    ctx.save()
    ctx.beginPath()
    ctx.arc(canvas.width / 2, canvas.height / 2, radius, 0, Math.PI * 2)
    ctx.clip()
  }

  ctx.drawImage(
    image,
    rect.x * scaleX,
    rect.y * scaleY,
    rect.width * scaleX,
    rect.height * scaleY
  )

  if (preset.mask === "circle") {
    ctx.restore()
  }

  return canvasToFile(canvas, file.name)
}

export async function renderImageCrop(
  file: File,
  preset: ImageCropPreset,
  modeOrTransform: ImageCropMode | ZoomPanTransform = DEFAULT_ZOOM_PAN_TRANSFORM,
  legacyOffset: ImageCropOffset = { x: 0, y: 0 }
): Promise<File> {
  if (
    typeof modeOrTransform === "object" &&
    modeOrTransform !== null &&
    "zoom" in modeOrTransform
  ) {
    return renderZoomPanCrop(file, preset, modeOrTransform)
  }

  if (modeOrTransform === "fill") {
    return renderZoomPanCrop(file, preset, {
      zoom: preset.maxZoom,
      offset: legacyOffset,
    })
  }

  return renderZoomPanCrop(file, preset, DEFAULT_ZOOM_PAN_TRANSFORM)
}
