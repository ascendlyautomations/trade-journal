import type { ImageCropPreset } from "./imageCropPresets"
import { fillFrameSize } from "./imageCropPresets"
import { TRADE_IMAGE_OUTPUT_WIDTH } from "./tradeImageAspect"

export type ImageCropMode = "fit" | "fill"

export type ImageCropOffset = { x: number; y: number }

export type ImageDrawRect = {
  x: number
  y: number
  width: number
  height: number
}

export function computeFitExportSize(
  imageWidth: number,
  imageHeight: number,
  maxWidth = TRADE_IMAGE_OUTPUT_WIDTH
): { width: number; height: number } {
  const scale = Math.min(1, maxWidth / imageWidth)
  return {
    width: Math.max(1, Math.round(imageWidth * scale)),
    height: Math.max(1, Math.round(imageHeight * scale)),
  }
}

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

export async function renderImageCrop(
  file: File,
  preset: ImageCropPreset,
  mode: ImageCropMode,
  offset: ImageCropOffset = { x: 0, y: 0 }
): Promise<File> {
  const image = await loadImageFromFile(file)
  const canvas = document.createElement("canvas")
  const ctx = canvas.getContext("2d")
  if (!ctx) {
    throw new Error("Could not prepare image canvas.")
  }

  if (mode === "fit" && preset.fitNatural) {
    const { width, height } = computeFitExportSize(
      image.naturalWidth,
      image.naturalHeight,
      preset.outputWidth
    )
    canvas.width = width
    canvas.height = height
    ctx.drawImage(image, 0, 0, width, height)
  } else {
    const frame = fillFrameSize(preset)
    canvas.width = preset.outputWidth
    canvas.height = preset.outputHeight
    const rect = computeFillDrawRect(
      image.naturalWidth,
      image.naturalHeight,
      offset,
      frame.width,
      frame.height
    )
    const scaleX = preset.outputWidth / frame.width
    const scaleY = preset.outputHeight / frame.height
    ctx.drawImage(
      image,
      rect.x * scaleX,
      rect.y * scaleY,
      rect.width * scaleX,
      rect.height * scaleY
    )
  }

  return canvasToFile(canvas, file.name)
}
