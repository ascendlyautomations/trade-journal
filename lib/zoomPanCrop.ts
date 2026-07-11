/** Zoom/pan crop math — zoom 1 = entire image visible inside the frame (Fit). */

export type ZoomPanOffset = { x: number; y: number }

export type ZoomPanTransform = {
  /** 1 = fit entire image; higher = zoom in. */
  zoom: number
  offset: ZoomPanOffset
}

export const ZOOM_PAN_MIN = 1
export const ZOOM_PAN_MAX = 4

export type ZoomPanDrawRect = {
  x: number
  y: number
  width: number
  height: number
}

export function computeFitScale(
  imageWidth: number,
  imageHeight: number,
  frameWidth: number,
  frameHeight: number
): number {
  if (imageWidth <= 0 || imageHeight <= 0) return 1
  return Math.min(frameWidth / imageWidth, frameHeight / imageHeight)
}

/**
 * Zoom multiplier (relative to Fit) so the image covers the frame with no letterbox.
 * Returns 1 when the image already covers at Fit scale (exact aspect match).
 */
export function computeCoverZoom(
  imageWidth: number,
  imageHeight: number,
  frameWidth: number,
  frameHeight: number,
  maxZoom = ZOOM_PAN_MAX
): number {
  if (imageWidth <= 0 || imageHeight <= 0 || frameWidth <= 0 || frameHeight <= 0) {
    return ZOOM_PAN_MIN
  }
  const fit = computeFitScale(imageWidth, imageHeight, frameWidth, frameHeight)
  if (fit <= 0) return ZOOM_PAN_MIN
  const cover = Math.max(frameWidth / imageWidth, frameHeight / imageHeight)
  return clampZoom(cover / fit, maxZoom)
}

export function clampZoom(zoom: number, maxZoom = ZOOM_PAN_MAX): number {
  return Math.min(maxZoom, Math.max(ZOOM_PAN_MIN, zoom))
}

export function computeZoomPanDrawRect(
  imageWidth: number,
  imageHeight: number,
  frameWidth: number,
  frameHeight: number,
  zoom: number,
  offset: ZoomPanOffset = { x: 0, y: 0 }
): ZoomPanDrawRect {
  const fitScale = computeFitScale(imageWidth, imageHeight, frameWidth, frameHeight)
  const scale = fitScale * clampZoom(zoom)
  const width = imageWidth * scale
  const height = imageHeight * scale

  let x = (frameWidth - width) / 2 + offset.x
  let y = (frameHeight - height) / 2 + offset.y

  if (width > frameWidth) {
    x = Math.min(0, Math.max(frameWidth - width, x))
  } else {
    x = (frameWidth - width) / 2
  }

  if (height > frameHeight) {
    y = Math.min(0, Math.max(frameHeight - height, y))
  } else {
    y = (frameHeight - height) / 2
  }

  return { x, y, width, height }
}

export function clampZoomPanOffset(
  imageWidth: number,
  imageHeight: number,
  frameWidth: number,
  frameHeight: number,
  zoom: number,
  offset: ZoomPanOffset
): ZoomPanOffset {
  const rect = computeZoomPanDrawRect(
    imageWidth,
    imageHeight,
    frameWidth,
    frameHeight,
    zoom,
    offset
  )
  const fitCenterX = (frameWidth - rect.width) / 2
  const fitCenterY = (frameHeight - rect.height) / 2

  if (rect.width <= frameWidth && rect.height <= frameHeight) {
    return { x: 0, y: 0 }
  }

  return {
    x: rect.x - fitCenterX,
    y: rect.y - fitCenterY,
  }
}

export const DEFAULT_ZOOM_PAN_TRANSFORM: ZoomPanTransform = {
  zoom: ZOOM_PAN_MIN,
  offset: { x: 0, y: 0 },
}
