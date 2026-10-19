export type StoryImageBaseFit = "contain" | "cover"

/** Base rect inside the 9:16 canvas, then user scale/offset (iOS uses contain; web editor uses cover). */
export function storyImageDrawRect(
  imageSize: { width: number; height: number },
  canvasSize: { width: number; height: number },
  scale: number,
  offset: { width: number; height: number },
  baseFit: StoryImageBaseFit = "cover"
): { x: number; y: number; width: number; height: number } {
  if (imageSize.width <= 0 || imageSize.height <= 0) {
    return { x: 0, y: 0, width: 0, height: 0 }
  }
  const imageAspect = imageSize.width / imageSize.height
  const canvasAspect = canvasSize.width / canvasSize.height

  let drawWidth: number
  let drawHeight: number
  if (baseFit === "cover") {
    if (imageAspect > canvasAspect) {
      drawHeight = canvasSize.height
      drawWidth = canvasSize.height * imageAspect
    } else {
      drawWidth = canvasSize.width
      drawHeight = canvasSize.width / imageAspect
    }
  } else if (imageAspect > canvasAspect) {
    drawWidth = canvasSize.width
    drawHeight = canvasSize.width / imageAspect
  } else {
    drawWidth = canvasSize.height * imageAspect
    drawHeight = canvasSize.height
  }
  drawWidth *= scale
  drawHeight *= scale

  const x = (canvasSize.width - drawWidth) / 2 + offset.width
  const y = (canvasSize.height - drawHeight) / 2 + offset.height
  return { x, y, width: drawWidth, height: drawHeight }
}
