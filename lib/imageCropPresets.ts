import { TRADE_IMAGE_ASPECT, TRADE_IMAGE_OUTPUT_WIDTH } from "./tradeImageAspect"

export type ImageCropPresetId = "content" | "avatar" | "story" | "room"

export type ImageCropMask = "none" | "circle" | "rounded"

export type ImageCropPreset = {
  id: ImageCropPresetId
  title: string
  subtitle: string
  /** Fill-frame width / height. */
  fillAspect: number
  outputWidth: number
  outputHeight: number
  modes: Array<"fit" | "fill">
  defaultMode: "fit" | "fill"
  /** Fit mode exports the image at its natural aspect ratio. */
  fitNatural: boolean
  mask: ImageCropMask
  fitHelp: string
  fillHelp: string
}

export const STORY_IMAGE_ASPECT = 400 / 700

export const IMAGE_CROP_PRESETS: Record<ImageCropPresetId, ImageCropPreset> = {
  content: {
    id: "content",
    title: "Adjust image",
    subtitle: "Choose how your image appears in the feed.",
    fillAspect: TRADE_IMAGE_ASPECT,
    outputWidth: TRADE_IMAGE_OUTPUT_WIDTH,
    outputHeight: Math.round(TRADE_IMAGE_OUTPUT_WIDTH / TRADE_IMAGE_ASPECT),
    modes: ["fit", "fill"],
    defaultMode: "fit",
    fitNatural: true,
    mask: "none",
    fitHelp: "Shows the full image at its natural proportions.",
    fillHelp: "Drag the image to choose what fills the frame.",
  },
  avatar: {
    id: "avatar",
    title: "Profile picture",
    subtitle: "Drag to position your photo in the circle.",
    fillAspect: 1,
    outputWidth: 512,
    outputHeight: 512,
    modes: ["fill"],
    defaultMode: "fill",
    fitNatural: false,
    mask: "circle",
    fitHelp: "",
    fillHelp: "Drag the image to center your face.",
  },
  story: {
    id: "story",
    title: "Story image",
    subtitle: "Drag to position your story.",
    fillAspect: STORY_IMAGE_ASPECT,
    outputWidth: 1080,
    outputHeight: Math.round(1080 / STORY_IMAGE_ASPECT),
    modes: ["fill"],
    defaultMode: "fill",
    fitNatural: false,
    mask: "rounded",
    fitHelp: "",
    fillHelp: "Drag the image to choose what fills the story frame.",
  },
  room: {
    id: "room",
    title: "Room picture",
    subtitle: "Drag to position your room image.",
    fillAspect: 1,
    outputWidth: 512,
    outputHeight: 512,
    modes: ["fill"],
    defaultMode: "fill",
    fitNatural: false,
    mask: "circle",
    fitHelp: "",
    fillHelp: "Drag the image to center the picture.",
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
