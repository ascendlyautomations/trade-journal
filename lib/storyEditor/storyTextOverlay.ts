export const STORY_CANVAS_ASPECT = 9 / 16
export const STORY_RENDER_WIDTH = 1080
export const STORY_RENDER_HEIGHT = 1920

export type StoryTextAlignment = "leading" | "center" | "trailing"

export type StoryTextColorPreset =
  | "white"
  | "black"
  | "accentBlue"
  | "accentGreen"
  | "accentRed"
  | "accentYellow"

export const STORY_TEXT_COLOR_PRESETS: StoryTextColorPreset[] = [
  "white",
  "black",
  "accentBlue",
  "accentGreen",
  "accentRed",
  "accentYellow",
]

export type StoryTextFill = {
  red: number
  green: number
  blue: number
  alpha: number
}

export type StoryTextOverlay = {
  id: string
  text: string
  /** Normalized center in canvas coordinates (0…1). */
  normalizedCenter: { x: number; y: number }
  scale: number
  rotationRadians: number
  textFill: StoryTextFill
  alignment: StoryTextAlignment
  showsBackground: boolean
}

export type StoryCanvasState = {
  imageScale: number
  imageOffset: { width: number; height: number }
  textOverlays: StoryTextOverlay[]
  selectedTextID: string | null
}

export function createEmptyStoryCanvasState(): StoryCanvasState {
  return {
    imageScale: 1,
    imageOffset: { width: 0, height: 0 },
    textOverlays: [],
    selectedTextID: null,
  }
}

export function storyTextFillFromPreset(preset: StoryTextColorPreset): StoryTextFill {
  switch (preset) {
    case "white":
      return { red: 1, green: 1, blue: 1, alpha: 1 }
    case "black":
      return { red: 0, green: 0, blue: 0, alpha: 1 }
    case "accentBlue":
      return { red: 0.35, green: 0.65, blue: 1, alpha: 1 }
    case "accentGreen":
      return { red: 0.35, green: 0.88, blue: 0.55, alpha: 1 }
    case "accentRed":
      return { red: 1, green: 0.35, blue: 0.35, alpha: 1 }
    case "accentYellow":
      return { red: 1, green: 0.88, blue: 0.25, alpha: 1 }
  }
}

export function storyTextFillCss(fill: StoryTextFill): string {
  const r = Math.round(fill.red * 255)
  const g = Math.round(fill.green * 255)
  const b = Math.round(fill.blue * 255)
  return `rgba(${r}, ${g}, ${b}, ${fill.alpha})`
}

export function storyTextFillMatchesPreset(
  fill: StoryTextFill,
  preset: StoryTextColorPreset,
  tolerance = 0.02
): boolean {
  const ref = storyTextFillFromPreset(preset)
  return (
    Math.abs(fill.red - ref.red) <= tolerance &&
    Math.abs(fill.green - ref.green) <= tolerance &&
    Math.abs(fill.blue - ref.blue) <= tolerance &&
    Math.abs(fill.alpha - ref.alpha) <= tolerance
  )
}

export function storyTextFillIsCustom(fill: StoryTextFill): boolean {
  return !STORY_TEXT_COLOR_PRESETS.some((p) => storyTextFillMatchesPreset(fill, p))
}

export function createStoryTextOverlay(
  partial?: Partial<StoryTextOverlay>
): StoryTextOverlay {
  return {
    id: partial?.id ?? crypto.randomUUID(),
    text: partial?.text ?? "",
    normalizedCenter: partial?.normalizedCenter ?? { x: 0.5, y: 0.45 },
    scale: partial?.scale ?? 1,
    rotationRadians: partial?.rotationRadians ?? 0,
    textFill: partial?.textFill ?? storyTextFillFromPreset("white"),
    alignment: partial?.alignment ?? "center",
    showsBackground: partial?.showsBackground ?? false,
  }
}

export const STORY_OVERLAY_SCALE_MIN = 0.5
export const STORY_OVERLAY_SCALE_MAX = 3

export function clampOverlayScale(scale: number): number {
  return Math.min(Math.max(scale, STORY_OVERLAY_SCALE_MIN), STORY_OVERLAY_SCALE_MAX)
}

export function publishableTextOverlays(
  overlays: StoryTextOverlay[]
): StoryTextOverlay[] {
  return overlays.filter((o) => o.text.trim().length > 0)
}

export function storyBaseFontSize(canvasWidth: number): number {
  return Math.max(22, canvasWidth * 0.065)
}

export function storyTextMaxWidth(canvasWidth: number): number {
  return canvasWidth * 0.82
}

export const STORY_TEXT_HIT_PADDING = 28
export const STORY_TEXT_MIN_HIT = { width: 96, height: 64 }

export const STORY_TRASH_METRICS = {
  iconSize: 44,
  canvasInset: 10,
  hitOutset: 44,
} as const

export function storyTrashVisibleFrame(canvasSize: { width: number; height: number }) {
  const { iconSize, canvasInset } = STORY_TRASH_METRICS
  return {
    x: canvasSize.width - canvasInset - iconSize,
    y: canvasInset,
    width: iconSize,
    height: iconSize,
  }
}

export function storyTrashHitZone(canvasSize: { width: number; height: number }) {
  const icon = storyTrashVisibleFrame(canvasSize)
  const o = STORY_TRASH_METRICS.hitOutset
  return {
    x: icon.x - o,
    y: icon.y - o,
    width: icon.width + o * 2,
    height: icon.height + o * 2,
  }
}

export function storyTrashContainsCenter(
  center: { x: number; y: number },
  canvasSize: { width: number; height: number }
): boolean {
  if (canvasSize.width <= 0 || canvasSize.height <= 0) return false
  const zone = storyTrashHitZone(canvasSize)
  return (
    center.x >= zone.x &&
    center.x <= zone.x + zone.width &&
    center.y >= zone.y &&
    center.y <= zone.y + zone.height
  )
}

export function clampNormalizedCenter(
  center: { x: number; y: number },
  canvasSize: { width: number; height: number },
  hitSize: { width: number; height: number }
): { x: number; y: number } {
  if (canvasSize.width <= 0 || canvasSize.height <= 0) return center
  const halfWidthNorm = hitSize.width / 2 / canvasSize.width
  const halfHeightNorm = hitSize.height / 2 / canvasSize.height
  const offscreenAllowance = 0.88
  const minX = -halfWidthNorm * offscreenAllowance
  const maxX = 1 + halfWidthNorm * offscreenAllowance
  const minY = -halfHeightNorm * offscreenAllowance
  const maxY = 1 + halfHeightNorm * offscreenAllowance
  return {
    x: Math.min(Math.max(center.x, minX), maxX),
    y: Math.min(Math.max(center.y, minY), maxY),
  }
}
