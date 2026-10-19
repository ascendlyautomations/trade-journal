import type { StoryCanvasState, StoryTextOverlay } from "./storyTextOverlay"
import {
  STORY_RENDER_HEIGHT,
  STORY_RENDER_WIDTH,
  storyBaseFontSize,
  storyTextMaxWidth,
} from "./storyTextOverlay"
import { storyImageDrawRect } from "./storyImageLayout"
import { measureStoryText, STORY_TEXT_FONT_STACK } from "./storyTextMetrics"

export type StoryRenderInput = {
  sourceImage: CanvasImageSource & { width: number; height: number }
  canvas: StoryCanvasState
  canvasSize: { width: number; height: number }
}

function alignmentCanvas(
  ctx: CanvasRenderingContext2D,
  alignment: StoryTextOverlay["alignment"]
) {
  if (alignment === "leading") ctx.textAlign = "left"
  else if (alignment === "trailing") ctx.textAlign = "right"
  else ctx.textAlign = "center"
}

function drawOverlay(
  ctx: CanvasRenderingContext2D,
  overlay: StoryTextOverlay,
  canvasSize: { width: number; height: number },
  pixelScale: number
) {
  const trimmed = overlay.text.trim()
  if (!trimmed) return

  const fontSize = storyBaseFontSize(canvasSize.width) * overlay.scale
  ctx.font = `600 ${fontSize}px ${STORY_TEXT_FONT_STACK}`
  const maxWidth = storyTextMaxWidth(canvasSize.width)
  const measured = measureStoryText(overlay, canvasSize.width)
  const textBounds = {
    width: measured.width,
    height: measured.height,
  }

  const centerX = overlay.normalizedCenter.x * canvasSize.width
  const centerY = overlay.normalizedCenter.y * canvasSize.height

  ctx.save()
  ctx.translate(centerX * pixelScale, centerY * pixelScale)
  ctx.rotate(overlay.rotationRadians)
  ctx.scale(pixelScale, pixelScale)

  let drawOriginX = -textBounds.width / 2
  const drawOriginY = -textBounds.height / 2
  if (overlay.alignment === "leading") {
    drawOriginX = -maxWidth / 2
  } else if (overlay.alignment === "trailing") {
    drawOriginX = maxWidth / 2 - textBounds.width
  }

  if (overlay.showsBackground) {
    const pad = 8
    const bgWidth = Math.max(textBounds.width, maxWidth) + pad * 2
    const bgHeight = textBounds.height + pad * 2
    const bgX = drawOriginX - pad
    const bgY = drawOriginY - pad
    ctx.fillStyle = "rgba(0, 0, 0, 0.45)"
    roundRect(ctx, bgX, bgY, bgWidth, bgHeight, 8)
    ctx.fill()
  }

  const fill = overlay.textFill
  ctx.fillStyle = `rgba(${fill.red * 255}, ${fill.green * 255}, ${fill.blue * 255}, ${fill.alpha})`
  alignmentCanvas(ctx, overlay.alignment)

  const lineHeight = fontSize * 1.15
  measured.lines.forEach((line, index) => {
    let x = drawOriginX
    if (overlay.alignment === "center") {
      x = drawOriginX + textBounds.width / 2
    } else if (overlay.alignment === "trailing") {
      x = drawOriginX + textBounds.width
    }
    ctx.fillText(line, x, drawOriginY + lineHeight * (index + 0.85))
  })

  ctx.restore()
}

function roundRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number
) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

export function renderStoryCanvasToCanvas(
  input: StoryRenderInput,
  targetCanvas: HTMLCanvasElement
): boolean {
  const { sourceImage, canvas, canvasSize } = input
  if (canvasSize.width <= 0 || canvasSize.height <= 0) return false

  const outputWidth = STORY_RENDER_WIDTH
  const outputHeight = STORY_RENDER_HEIGHT
  targetCanvas.width = outputWidth
  targetCanvas.height = outputHeight
  const ctx = targetCanvas.getContext("2d")
  if (!ctx) return false

  const pixelScale = outputWidth / canvasSize.width

  ctx.fillStyle = "#000000"
  ctx.fillRect(0, 0, outputWidth, outputHeight)

  const imageRect = storyImageDrawRect(
    { width: sourceImage.width, height: sourceImage.height },
    canvasSize,
    canvas.imageScale,
    canvas.imageOffset
  )
  ctx.drawImage(
    sourceImage,
    imageRect.x * pixelScale,
    imageRect.y * pixelScale,
    imageRect.width * pixelScale,
    imageRect.height * pixelScale
  )

  for (const overlay of canvas.textOverlays) {
    if (!overlay.text.trim()) continue
    drawOverlay(ctx, overlay, canvasSize, pixelScale)
  }

  return true
}

export function loadImageFromFile(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve(img)
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error("Couldn't load story image"))
    }
    img.src = url
  })
}

export async function renderStoryToBlob(
  input: StoryRenderInput,
  mimeType = "image/jpeg",
  quality = 0.92
): Promise<Blob> {
  const canvas = document.createElement("canvas")
  const ok = renderStoryCanvasToCanvas(input, canvas)
  if (!ok) throw new Error("Couldn't render story")
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (!blob) reject(new Error("Couldn't render story"))
        else resolve(blob)
      },
      mimeType,
      quality
    )
  })
}

export async function renderStoryToFile(
  input: StoryRenderInput,
  fileName = "story.jpg"
): Promise<File> {
  const blob = await renderStoryToBlob(input)
  return new File([blob], fileName, { type: blob.type || "image/jpeg" })
}
