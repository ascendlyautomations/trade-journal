/**
 * Content Image V2 — iOS content-image contract.
 * Isolated from the legacy `content` preset (4:3 / 1200×900 WebP).
 * Trades, posts, and achievements import this preset. Other image types do not.
 */

export const CONTENT_IMAGE_V2_MIN_ZOOM = 1
export const CONTENT_IMAGE_V2_MAX_ZOOM = 4
export const CONTENT_IMAGE_V2_MAX_EDGE = 2560
export const CONTENT_IMAGE_V2_JPEG_QUALITY = 0.92
export const CONTENT_IMAGE_V2_MIME = "image/jpeg"

/** Crop-modal preset id for trades, posts, and achievements. */
export const CONTENT_IMAGE_V2_PRESET = "contentV2" as const
export type ContentImageV2Preset = typeof CONTENT_IMAGE_V2_PRESET
export const CONTENT_IMAGE_V2_ENCODE_PASSES = 1
/** Tallest portrait ratio (width / height). Matches iOS FeedMediaLayout. */
export const CONTENT_FEED_MIN_ASPECT = 4 / 5
/** Shared preview/export coordinate space. Crop pixels do not depend on CSS size. */
export const CONTENT_IMAGE_V2_LOGICAL_FRAME_WIDTH = 1000

export type ContentImageAspect = "square" | "portrait" | "landscape"

/** New content uploads. 4:5 is the phone-first default. */
export const CONTENT_IMAGE_V2_DEFAULT_ASPECT: ContentImageAspect = "portrait"

export const CONTENT_IMAGE_ASPECTS: ContentImageAspect[] = [
  "square",
  "portrait",
  "landscape",
]

export type ContentCoverTransform = {
  /** 1 = minimum cover (frame filled). 4 = 4× that cover. */
  zoom: number
  offset: { x: number; y: number }
}

export const DEFAULT_CONTENT_COVER_TRANSFORM: ContentCoverTransform = {
  zoom: CONTENT_IMAGE_V2_MIN_ZOOM,
  offset: { x: 0, y: 0 },
}

export type ContentFrame = { width: number; height: number }

export type ContentCropRect = {
  x: number
  y: number
  width: number
  height: number
}

export type ContentOutputSize = {
  width: number
  height: number
  /** 1 when the crop is already within the longest-edge cap. Never greater than 1. */
  scale: number
}

export type ContentCoverLayout = {
  zoom: number
  offset: { x: number; y: number }
  originX: number
  originY: number
  displayWidth: number
  displayHeight: number
  totalScale: number
}

export type ContentImageExportPlan = {
  aspectRatio: number
  frame: ContentFrame
  layout: ContentCoverLayout
  crop: ContentCropRect
  output: ContentOutputSize
  mime: typeof CONTENT_IMAGE_V2_MIME
  quality: typeof CONTENT_IMAGE_V2_JPEG_QUALITY
  encodePasses: typeof CONTENT_IMAGE_V2_ENCODE_PASSES
}

/** Presentation aspect (width / height) for the selected ratio. */
export function contentPresentationAspect(option: ContentImageAspect): number {
  switch (option) {
    case "square":
      return 1
    case "portrait":
      return CONTENT_FEED_MIN_ASPECT
    case "landscape":
      return 16 / 9
  }
}

export function contentAspectLabel(option: ContentImageAspect): string {
  switch (option) {
    case "square":
      return "1:1"
    case "portrait":
      return "4:5"
    case "landscape":
      return "16:9"
  }
}

export function contentLogicalFrame(aspectRatio: number): ContentFrame {
  const width = CONTENT_IMAGE_V2_LOGICAL_FRAME_WIDTH
  const height = width / Math.max(aspectRatio, 0.01)
  return { width, height }
}

export function clampContentZoom(zoom: number): number {
  if (!Number.isFinite(zoom)) return CONTENT_IMAGE_V2_MIN_ZOOM
  return Math.min(
    CONTENT_IMAGE_V2_MAX_ZOOM,
    Math.max(CONTENT_IMAGE_V2_MIN_ZOOM, zoom)
  )
}

/**
 * Aspect-fill layout. Zoom 1 covers the frame. Pan cannot reveal empty frame.
 */
export function contentCoverLayout(
  imageWidth: number,
  imageHeight: number,
  frame: ContentFrame,
  transform: ContentCoverTransform
): ContentCoverLayout {
  const safeW = Math.max(imageWidth, 1)
  const safeH = Math.max(imageHeight, 1)
  const base = Math.max(frame.width / safeW, frame.height / safeH)
  const zoom = clampContentZoom(transform.zoom)
  const totalScale = base * zoom
  const displayWidth = safeW * totalScale
  const displayHeight = safeH * totalScale
  const centeredX = (frame.width - displayWidth) / 2
  const centeredY = (frame.height - displayHeight) / 2
  const proposedX = centeredX + (Number.isFinite(transform.offset.x) ? transform.offset.x : 0)
  const proposedY = centeredY + (Number.isFinite(transform.offset.y) ? transform.offset.y : 0)
  const originX = Math.min(0, Math.max(frame.width - displayWidth, proposedX))
  const originY = Math.min(0, Math.max(frame.height - displayHeight, proposedY))
  return {
    zoom,
    offset: { x: originX - centeredX, y: originY - centeredY },
    originX,
    originY,
    displayWidth,
    displayHeight,
    totalScale,
  }
}

export function clampContentCoverTransform(
  imageWidth: number,
  imageHeight: number,
  aspect: ContentImageAspect,
  transform: ContentCoverTransform
): ContentCoverTransform {
  const frame = contentLogicalFrame(contentPresentationAspect(aspect))
  const layout = contentCoverLayout(imageWidth, imageHeight, frame, transform)
  return { zoom: layout.zoom, offset: layout.offset }
}

/** Source pixels visible through the crop frame. */
export function contentSourceCropRect(
  imageWidth: number,
  imageHeight: number,
  frame: ContentFrame,
  layout: ContentCoverLayout
): ContentCropRect {
  const scale = layout.totalScale
  if (scale <= 0 || imageWidth <= 0 || imageHeight <= 0) {
    return { x: 0, y: 0, width: Math.max(imageWidth, 1), height: Math.max(imageHeight, 1) }
  }
  const unclampedX = -layout.originX / scale
  const unclampedY = -layout.originY / scale
  const unclampedW = frame.width / scale
  const unclampedH = frame.height / scale
  const left = Math.max(0, unclampedX)
  const top = Math.max(0, unclampedY)
  const right = Math.min(imageWidth, unclampedX + unclampedW)
  const bottom = Math.min(imageHeight, unclampedY + unclampedH)
  return {
    x: left,
    y: top,
    width: Math.max(1, right - left),
    height: Math.max(1, bottom - top),
  }
}

/** Longest-edge cap. Scale is never above 1. */
export function contentOutputSize(
  cropWidth: number,
  cropHeight: number
): ContentOutputSize {
  const longest = Math.max(cropWidth, cropHeight)
  const scale =
    longest > CONTENT_IMAGE_V2_MAX_EDGE && longest > 0
      ? CONTENT_IMAGE_V2_MAX_EDGE / longest
      : 1
  return {
    width: Math.max(1, Math.floor(cropWidth * scale)),
    height: Math.max(1, Math.floor(cropHeight * scale)),
    scale,
  }
}

export function planContentImageExport(
  imageWidth: number,
  imageHeight: number,
  aspect: ContentImageAspect,
  transform: ContentCoverTransform = DEFAULT_CONTENT_COVER_TRANSFORM
): ContentImageExportPlan {
  const aspectRatio = contentPresentationAspect(aspect)
  const frame = contentLogicalFrame(aspectRatio)
  const layout = contentCoverLayout(imageWidth, imageHeight, frame, transform)
  const crop = contentSourceCropRect(imageWidth, imageHeight, frame, layout)
  const output = contentOutputSize(crop.width, crop.height)
  return {
    aspectRatio,
    frame,
    layout,
    crop,
    output,
    mime: CONTENT_IMAGE_V2_MIME,
    quality: CONTENT_IMAGE_V2_JPEG_QUALITY,
    encodePasses: CONTENT_IMAGE_V2_ENCODE_PASSES,
  }
}

export function contentJpegFileName(originalName: string): string {
  const trimmed = originalName.trim()
  const base = trimmed.replace(/\.[^/.]+$/, "") || "image"
  return `${base}.jpg`
}

/**
 * Visual pixel size after EXIF orientation is baked.
 * Orientations 5–8 swap width and height. The uploaded JPEG must not rely on EXIF.
 */
export function orientedPixelSize(
  width: number,
  height: number,
  exifOrientation: number
): { width: number; height: number } {
  switch (exifOrientation) {
    case 5:
    case 6:
    case 7:
    case 8:
      return { width: height, height: width }
    default:
      return { width, height }
  }
}

export function imageDecodeErrorMessage(file: { type?: string; name?: string }): string {
  const type = (file.type ?? "").toLowerCase()
  const name = (file.name ?? "").toLowerCase()
  if (
    type.includes("heic") ||
    type.includes("heif") ||
    name.endsWith(".heic") ||
    name.endsWith(".heif")
  ) {
    return "This browser can't read that HEIC photo. Export it as JPEG and try again."
  }
  return "Couldn't read that image. Try a JPEG or PNG."
}

export function isHeicFile(file: { type?: string; name?: string }): boolean {
  const type = (file.type ?? "").toLowerCase()
  const name = (file.name ?? "").toLowerCase()
  return (
    type.includes("heic") ||
    type.includes("heif") ||
    name.endsWith(".heic") ||
    name.endsWith(".heif")
  )
}
