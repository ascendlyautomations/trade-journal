import {
  CONTENT_IMAGE_V2_JPEG_QUALITY,
  CONTENT_IMAGE_V2_MIME,
  contentJpegFileName,
  imageDecodeErrorMessage,
  planContentImageExport,
  type ContentCoverTransform,
  type ContentImageAspect,
} from "./contentImageV2"

export type RenderContentImageV2Options = {
  aspect: ContentImageAspect
  transform: ContentCoverTransform
}

/**
 * Final content-image encode. One JPEG at the V2 quality constant.
 * Orientation is baked by createImageBitmap({ imageOrientation: "from-image" }).
 */
export async function renderContentImageV2(
  file: File,
  options: RenderContentImageV2Options
): Promise<File> {
  const bitmap = await decodeOrientedImage(file)
  try {
    const plan = planContentImageExport(
      bitmap.width,
      bitmap.height,
      options.aspect,
      options.transform
    )
    const canvas = document.createElement("canvas")
    canvas.width = plan.output.width
    canvas.height = plan.output.height
    const context = canvas.getContext("2d")
    if (!context) {
      throw new Error("Could not prepare image canvas.")
    }
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
    const blob = await canvasToJpegBlob(canvas)
    return new File([blob], contentJpegFileName(file.name), {
      type: CONTENT_IMAGE_V2_MIME,
    })
  } finally {
    bitmap.close()
  }
}

/** EXIF-aware decode — same pixels used for export and crop preview. */
export async function decodeOrientedImageBitmap(file: File): Promise<ImageBitmap> {
  if (typeof createImageBitmap !== "function") {
    throw new Error(imageDecodeErrorMessage(file))
  }
  try {
    return await createImageBitmap(file, { imageOrientation: "from-image" })
  } catch {
    throw new Error(imageDecodeErrorMessage(file))
  }
}

export type OrientedCropPreview = {
  previewUrl: string
  width: number
  height: number
  dispose: () => void
}

/**
 * Upright preview URL for the crop editor (PNG blob). Matches export orientation.
 */
export async function loadOrientedCropPreview(file: File): Promise<OrientedCropPreview> {
  const bitmap = await decodeOrientedImageBitmap(file)
  try {
    const canvas = document.createElement("canvas")
    canvas.width = bitmap.width
    canvas.height = bitmap.height
    const context = canvas.getContext("2d")
    if (!context) {
      throw new Error("Could not prepare image canvas.")
    }
    context.drawImage(bitmap, 0, 0)
    const blob = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(
        (value) => {
          if (!value) {
            reject(new Error("Could not prepare preview."))
            return
          }
          resolve(value)
        },
        "image/png"
      )
    })
    const previewUrl = URL.createObjectURL(blob)
    return {
      previewUrl,
      width: bitmap.width,
      height: bitmap.height,
      dispose: () => URL.revokeObjectURL(previewUrl),
    }
  } finally {
    bitmap.close()
  }
}

async function decodeOrientedImage(file: File): Promise<ImageBitmap> {
  return decodeOrientedImageBitmap(file)
}

function canvasToJpegBlob(canvas: HTMLCanvasElement): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (!blob) {
          reject(new Error("Could not encode JPEG."))
          return
        }
        resolve(blob)
      },
      CONTENT_IMAGE_V2_MIME,
      CONTENT_IMAGE_V2_JPEG_QUALITY
    )
  })
}
