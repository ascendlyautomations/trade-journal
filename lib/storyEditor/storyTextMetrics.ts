import type { StoryTextOverlay } from "./storyTextOverlay"
import {
  storyBaseFontSize,
  storyTextMaxWidth,
} from "./storyTextOverlay"

/** Canvas + DOM story overlay font stack (weight applied separately). */
export const STORY_TEXT_FONT_STACK =
  'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'

export type MeasuredStoryText = {
  width: number
  height: number
  lines: string[]
}

export function measureStoryText(
  overlay: StoryTextOverlay,
  canvasWidth: number
): MeasuredStoryText {
  if (typeof document === "undefined") {
    return { width: 0, height: 0, lines: [] }
  }
  const canvas = document.createElement("canvas")
  const ctx = canvas.getContext("2d")
  if (!ctx) return { width: 0, height: 0, lines: [] }

  const trimmed = overlay.text.trim()
  if (!trimmed) {
    return { width: 4, height: storyBaseFontSize(canvasWidth) * overlay.scale, lines: [" "] }
  }

  const fontSize = storyBaseFontSize(canvasWidth) * overlay.scale
  ctx.font = `600 ${fontSize}px ${STORY_TEXT_FONT_STACK}`
  const maxWidth = storyTextMaxWidth(canvasWidth)
  const lines = wrapText(ctx, trimmed, maxWidth)
  let width = 0
  for (const line of lines) {
    width = Math.max(width, ctx.measureText(line).width)
  }
  const lineHeight = fontSize * 1.15
  const height = lines.length * lineHeight
  return { width, height, lines }
}

function wrapText(
  ctx: CanvasRenderingContext2D,
  text: string,
  maxWidth: number
): string[] {
  const paragraphs = text.split("\n")
  const lines: string[] = []
  for (const paragraph of paragraphs) {
    const words = paragraph.split(/\s+/).filter(Boolean)
    if (words.length === 0) {
      lines.push("")
      continue
    }
    let current = words[0]
    for (let i = 1; i < words.length; i++) {
      const next = `${current} ${words[i]}`
      if (ctx.measureText(next).width <= maxWidth) {
        current = next
      } else {
        lines.push(current)
        current = words[i]
      }
    }
    lines.push(current)
  }
  return lines.length ? lines : [text]
}

export function storyOverlayFontSize(canvasWidth: number, scale: number): number {
  return storyBaseFontSize(canvasWidth) * scale
}

