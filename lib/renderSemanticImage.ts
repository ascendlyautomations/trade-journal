import {
  DEFAULT_CONTENT_COVER_TRANSFORM,
  imageDecodeErrorMessage,
  type ContentCoverTransform,
} from "./contentImageV2"
import {
  ATTACHMENT_JPEG_QUALITY,
  ATTACHMENT_MAX_EDGE,
  CHAT_JPEG_QUALITY,
  CHAT_MAX_EDGE,
  planBoundedOriginal,
  planFixedCover,
  SEMANTIC_JPEG_MIME,
  semanticJpegFileName,
  type FixedCoverKind,
} from "./semanticImage"

export type BoundedImageKind = "chat" | "attachment"

async function decodeOrientedImage(file: File): Promise<ImageBitmap> {
  if (typeof createImageBitmap !== "function") {
    throw new Error(imageDecodeErrorMessage(file))
  }
  try {
    return await createImageBitmap(file, { imageOrientation: "from-image" })
  } catch {
    throw new Error(imageDecodeErrorMessage(file))
  }
}

function canvasToJpegBlob(
  canvas: HTMLCanvasElement,
  quality: number
): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (!blob) {
          reject(new Error("Could not encode JPEG."))
          return
        }
        resolve(blob)
      },
      SEMANTIC_JPEG_MIME,
      quality
    )
  })
}

/** Square avatar/room image, or a 9:16 story. One JPEG. Cover crop is baked. */
export async function renderFixedCoverImage(
  file: File,
  options: {
    kind: FixedCoverKind
    transform?: ContentCoverTransform
  }
): Promise<File> {
  const bitmap = await decodeOrientedImage(file)
  try {
    const plan = planFixedCover(
      bitmap.width,
      bitmap.height,
      options.kind,
      options.transform ?? DEFAULT_CONTENT_COVER_TRANSFORM
    )
    const canvas = document.createElement("canvas")
    canvas.width = plan.output.width
    canvas.height = plan.output.height
    const context = canvas.getContext("2d")
    if (!context) throw new Error("Could not prepare image canvas.")
    context.drawImage(
      bitmap,
      plan.crop.x,
      plan.crop.y,
      plan.crop.width,
      plan.crop.height,
      0,
      0,
      plan.output.width,
      plan.output.height
    )
    const blob = await canvasToJpegBlob(canvas, plan.output.quality)
    return new File([blob], semanticJpegFileName(file.name), {
      type: SEMANTIC_JPEG_MIME,
    })
  } finally {
    bitmap.close()
  }
}

/**
 * Original-aspect JPEG for chat photos and screenshot attachments.
 * Chat smooths the downscale. Attachments keep smoothing off so UI text
 * stays closer to the previous screenshot pipeline.
 */
export async function renderBoundedJpeg(
  file: File,
  kind: BoundedImageKind
): Promise<File> {
  const bitmap = await decodeOrientedImage(file)
  try {
    const maxEdge = kind === "chat" ? CHAT_MAX_EDGE : ATTACHMENT_MAX_EDGE
    const quality = kind === "chat" ? CHAT_JPEG_QUALITY : ATTACHMENT_JPEG_QUALITY
    const output = planBoundedOriginal(bitmap.width, bitmap.height, maxEdge)
    const canvas = document.createElement("canvas")
    canvas.width = output.width
    canvas.height = output.height
    const context = canvas.getContext("2d")
    if (!context) throw new Error("Could not prepare image canvas.")
    context.imageSmoothingEnabled = kind !== "attachment"
    context.drawImage(bitmap, 0, 0, output.width, output.height)
    const blob = await canvasToJpegBlob(canvas, quality)
    return new File([blob], semanticJpegFileName(file.name), {
      type: SEMANTIC_JPEG_MIME,
    })
  } finally {
    bitmap.close()
  }
}
