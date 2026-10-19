import {
  loadImageFromFile,
  renderStoryToFile,
} from "./storyImageRenderer"
import type { StoryCanvasState } from "./storyTextOverlay"

/** Bakes the unified story editor canvas (image transform + text) to 1080×1920. */
export async function prepareStoryUploadFile(
  sourceFile: File,
  canvas: StoryCanvasState,
  canvasSize: { width: number; height: number }
): Promise<File> {
  if (canvasSize.width <= 0 || canvasSize.height <= 0) {
    throw new Error("Story editor is still loading")
  }
  const img = await loadImageFromFile(sourceFile)
  return renderStoryToFile({
    sourceImage: img,
    canvas,
    canvasSize,
  })
}
