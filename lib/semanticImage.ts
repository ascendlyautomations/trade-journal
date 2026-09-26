import {
  CONTENT_IMAGE_V2_MIME,
  contentCoverLayout,
  contentJpegFileName,
  contentLogicalFrame,
  contentSourceCropRect,
  DEFAULT_CONTENT_COVER_TRANSFORM,
  type ContentCoverTransform,
} from "./contentImageV2"

/** Square avatar, room picture, and group avatar. Circle is display-only. */
export const AVATAR_OUTPUT_SIZE = 512
export const AVATAR_JPEG_QUALITY = 0.92

/** Story canvas. 9:16, not the legacy 400/700 preview frame. */
export const STORY_OUTPUT_WIDTH = 1080
export const STORY_OUTPUT_HEIGHT = 1920
export const STORY_ASPECT = STORY_OUTPUT_WIDTH / STORY_OUTPUT_HEIGHT
export const STORY_JPEG_QUALITY = 0.92

/**
 * Chat photos keep their aspect. 2560 is the web cap.
 * Native chat is still uncapped; that difference is intentional.
 */
export const CHAT_MAX_EDGE = 2560
export const CHAT_JPEG_QUALITY = 0.82

/**
 * Bug, feedback, support, and suggestion screenshots.
 * Quality matches the specified attachment default. Downscale smoothing is off
 * so UI text stays closer to the existing screenshot preset.
 */
export const ATTACHMENT_MAX_EDGE = 2560
export const ATTACHMENT_JPEG_QUALITY = 0.82

export const SEMANTIC_JPEG_MIME = CONTENT_IMAGE_V2_MIME

export type FixedCoverKind = "avatar" | "story"

export function fixedCoverOutput(kind: FixedCoverKind): {
  width: number
  height: number
  quality: number
} {
  if (kind === "story") {
    return {
      width: STORY_OUTPUT_WIDTH,
      height: STORY_OUTPUT_HEIGHT,
      quality: STORY_JPEG_QUALITY,
    }
  }
  return {
    width: AVATAR_OUTPUT_SIZE,
    height: AVATAR_OUTPUT_SIZE,
    quality: AVATAR_JPEG_QUALITY,
  }
}

export function planFixedCover(
  imageWidth: number,
  imageHeight: number,
  kind: FixedCoverKind,
  transform: ContentCoverTransform = DEFAULT_CONTENT_COVER_TRANSFORM
) {
  const output = fixedCoverOutput(kind)
  const frame = contentLogicalFrame(output.width / output.height)
  const layout = contentCoverLayout(imageWidth, imageHeight, frame, transform)
  const crop = contentSourceCropRect(imageWidth, imageHeight, frame, layout)
  return { frame, layout, crop, output }
}

/** Original aspect, never upscaled, longest edge at most maxEdge. */
export function planBoundedOriginal(
  width: number,
  height: number,
  maxEdge: number
): { width: number; height: number; scale: number } {
  const longest = Math.max(width, height)
  const scale = longest > maxEdge && longest > 0 ? maxEdge / longest : 1
  return {
    width: Math.max(1, Math.floor(width * scale)),
    height: Math.max(1, Math.floor(height * scale)),
    scale,
  }
}

export function semanticJpegFileName(originalName: string): string {
  return contentJpegFileName(originalName)
}
