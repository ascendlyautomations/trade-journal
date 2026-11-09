import type { ScreenCameraOverlayPosition } from "./tradeRoomBroadcastScreenOverlayTypes.ts"

/** PiP width as a fraction of the composite canvas width. */
export const SCREEN_OVERLAY_PIP_WIDTH_RATIO = 0.22
/** Outer margin as a fraction of the shorter canvas edge. */
export const SCREEN_OVERLAY_MARGIN_RATIO = 0.025
export const SCREEN_OVERLAY_CORNER_RADIUS_PX = 10

export function screenOverlayPipRect(options: {
  canvasWidth: number
  canvasHeight: number
  pipWidth: number
  pipHeight: number
  position: ScreenCameraOverlayPosition
}): { x: number; y: number } {
  const margin =
    Math.min(options.canvasWidth, options.canvasHeight) *
    SCREEN_OVERLAY_MARGIN_RATIO
  const { pipWidth: w, pipHeight: h } = options

  switch (options.position) {
    case "top-left":
      return { x: margin, y: margin }
    case "top-right":
      return { x: options.canvasWidth - w - margin, y: margin }
    case "bottom-left":
      return { x: margin, y: options.canvasHeight - h - margin }
    case "bottom-right":
    default:
      return {
        x: options.canvasWidth - w - margin,
        y: options.canvasHeight - h - margin,
      }
  }
}

export function screenOverlayPipSize(options: {
  canvasWidth: number
  cameraWidth: number
  cameraHeight: number
}): { width: number; height: number } {
  const width = Math.max(
    120,
    Math.round(options.canvasWidth * SCREEN_OVERLAY_PIP_WIDTH_RATIO)
  )
  const aspect =
    options.cameraWidth > 0 && options.cameraHeight > 0
      ? options.cameraWidth / options.cameraHeight
      : 16 / 9
  const height = Math.round(width / aspect)
  return { width, height }
}
