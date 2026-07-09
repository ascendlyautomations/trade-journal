import { TRADE_IMAGE_ASPECT, TRADE_IMAGE_OUTPUT_WIDTH } from "./tradeImageAspect"
import { TRADE_IMAGE_LETTERBOX_COLOR } from "./tradeImageAspect"
import { ZOOM_PAN_MAX } from "./zoomPanCrop"

export type ImageCropPresetId = "content" | "avatar" | "story" | "room"

export type ImageCropMask = "none" | "circle" | "rounded"

export type ImageCropPreset = {
  id: ImageCropPresetId
  title: string
  subtitle: string
  /** Fixed crop frame width / height. */
  fillAspect: number
  outputWidth: number
  outputHeight: number
  maxZoom: number
  letterboxColor: string
  mask: ImageCropMask
  /** @deprecated Legacy fit export */
  fitNatural?: boolean
  /** @deprecated */
  modes?: Array<"fit" | "fill">
  /** @deprecated */
  defaultMode?: "fit" | "fill"
  /** @deprecated */
  fitHelp?: string
  /** @deprecated */
  fillHelp?: string
}

export const STORY_IMAGE_ASPECT = 400 / 700

const sharedHelp =
  "Drag to reposition. Pinch or use the slider to zoom. Reset returns to full image (Fit)."

export const IMAGE_CROP_PRESETS: Record<ImageCropPresetId, ImageCropPreset> = {
  content: {
    id: "content",
    title: "Adjust image",
    subtitle: "Drag and zoom to choose what appears in your post.",
    fillAspect: TRADE_IMAGE_ASPECT,
    outputWidth: TRADE_IMAGE_OUTPUT_WIDTH,
    outputHeight: Math.round(TRADE_IMAGE_OUTPUT_WIDTH / TRADE_IMAGE_ASPECT),
    maxZoom: ZOOM_PAN_MAX,
    letterboxColor: TRADE_IMAGE_LETTERBOX_COLOR,
    mask: "none",
    fitNatural: true,
  },
  avatar: {
    id: "avatar",
    title: "Profile picture",
    subtitle: "Drag and zoom to position your photo.",
    fillAspect: 1,
    outputWidth: 512,
    outputHeight: 512,
    maxZoom: ZOOM_PAN_MAX,
    letterboxColor: TRADE_IMAGE_LETTERBOX_COLOR,
    mask: "circle",
  },
  story: {
    id: "story",
    title: "Story image",
    subtitle: "Drag and zoom to position your story.",
    fillAspect: STORY_IMAGE_ASPECT,
    outputWidth: 1080,
    outputHeight: Math.round(1080 / STORY_IMAGE_ASPECT),
    maxZoom: ZOOM_PAN_MAX,
    letterboxColor: TRADE_IMAGE_LETTERBOX_COLOR,
    mask: "rounded",
  },
  room: {
    id: "room",
    title: "Room picture",
    subtitle: "Drag and zoom to position your room image.",
    fillAspect: 1,
    outputWidth: 512,
    outputHeight: 512,
    maxZoom: ZOOM_PAN_MAX,
    letterboxColor: TRADE_IMAGE_LETTERBOX_COLOR,
    mask: "circle",
  },
}

export function getImageCropPreset(id: ImageCropPresetId): ImageCropPreset {
  return IMAGE_CROP_PRESETS[id]
}

export function fillFrameSize(preset: ImageCropPreset): {
  width: number
  height: number
} {
  return {
    width: preset.outputWidth,
    height: Math.round(preset.outputWidth / preset.fillAspect),
  }
}

export const IMAGE_CROP_EDITOR_HELP = sharedHelp
