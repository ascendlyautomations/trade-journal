import { getImageCropPreset } from "./imageCropPresets"
import {
  clampFillOffset,
  computeFillDrawRect,
  computeFitExportSize,
  renderImageCrop,
  type ImageCropMode,
  type ImageCropOffset,
} from "./renderImageCrop"
import {
  TRADE_IMAGE_ASPECT,
  TRADE_IMAGE_OUTPUT_HEIGHT,
  TRADE_IMAGE_OUTPUT_WIDTH,
} from "./tradeImageAspect"

export type TradeImageCropMode = ImageCropMode
export type TradeImageCropOffset = ImageCropOffset
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
  const scale = Math.min(frameWidth / imageWidth, frameHeight / imageHeight)
  const width = imageWidth * scale
  const height = imageHeight * scale
  return {
    x: (frameWidth - width) / 2,
    y: (frameHeight - height) / 2,
    width,
    height,
  }
}

export {
  clampFillOffset,
  computeFillDrawRect,
  computeFitExportSize,
}

export async function renderTradeImageCrop(
  file: File,
  mode: TradeImageCropMode,
  offset: ImageCropOffset = { x: 0, y: 0 }
): Promise<File> {
  return renderImageCrop(file, CONTENT_PRESET, mode, offset)
}

export {
  TRADE_IMAGE_ASPECT,
  TRADE_IMAGE_OUTPUT_HEIGHT,
  TRADE_IMAGE_OUTPUT_WIDTH,
}
