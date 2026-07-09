import { getImageCropPreset } from "./imageCropPresets"
import {
  computeFillDrawRect,
  computeFitExportSize,
  renderZoomPanCrop,
  type ZoomPanTransform,
} from "./renderImageCrop"
import {
  computeFitScale,
  computeZoomPanDrawRect,
  DEFAULT_ZOOM_PAN_TRANSFORM,
} from "./zoomPanCrop"
import {
  TRADE_IMAGE_ASPECT,
  TRADE_IMAGE_OUTPUT_HEIGHT,
  TRADE_IMAGE_OUTPUT_WIDTH,
} from "./tradeImageAspect"

/** @deprecated Use ZoomPanTransform */
export type TradeImageCropMode = "fit" | "fill"
/** @deprecated Use ZoomPanOffset */
export type TradeImageCropOffset = { x: number; y: number }
export type TradeImageDrawRect = {
  x: number
  y: number
  width: number
  height: number
}

const CONTENT_PRESET = getImageCropPreset("content")

export function computeFitDrawRect(
  imageWidth: number,
  imageHeight: number,
  frameWidth = TRADE_IMAGE_OUTPUT_WIDTH,
  frameHeight = TRADE_IMAGE_OUTPUT_HEIGHT
): TradeImageDrawRect {
  return computeZoomPanDrawRect(
    imageWidth,
    imageHeight,
    frameWidth,
    frameHeight,
    1,
    { x: 0, y: 0 }
  )
}

export { computeFillDrawRect, computeFitExportSize, computeFitScale }

export async function renderTradeImageCrop(
  file: File,
  transform: ZoomPanTransform = DEFAULT_ZOOM_PAN_TRANSFORM
): Promise<File> {
  return renderZoomPanCrop(file, CONTENT_PRESET, transform)
}

export {
  TRADE_IMAGE_ASPECT,
  TRADE_IMAGE_OUTPUT_HEIGHT,
  TRADE_IMAGE_OUTPUT_WIDTH,
}
