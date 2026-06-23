export type ImageCompressPreset = "default" | "screenshot"

const PRESET_CONFIG = {
  default: {
    maxWidth: 1200,
    quality: 0.92,
    preservePng: false,
    skipWhenWithinLimits: false,
    crispDownscale: false,
  },
  screenshot: {
    maxWidth: 2560,
    quality: 0.95,
    preservePng: true,
    skipWhenWithinLimits: true,
    crispDownscale: true,
  },
} as const

export type CompressImageOptions = {
  preset?: ImageCompressPreset
}

function logImagePipeline(
  stage: string,
  details: Record<string, unknown>
) {
  if (process.env.NODE_ENV === "development") {
    console.debug(`[image-pipeline] ${stage}`, details)
  }
}

function resolveOutputType(
  inputType: string,
  preset: ImageCompressPreset
): { mime: string; extension: string } {
  const config = PRESET_CONFIG[preset]
  if (config.preservePng && inputType === "image/png") {
    return { mime: "image/png", extension: "png" }
  }
  return { mime: "image/webp", extension: "webp" }
}

export async function compressImage(
  file: File,
  options?: CompressImageOptions
): Promise<File> {
  const preset = options?.preset ?? "default"
  const config = PRESET_CONFIG[preset]

  if (!file.type?.startsWith("image/")) return file

  const img = document.createElement("img")
  const canvas = document.createElement("canvas")
  const ctx = canvas.getContext("2d")

  if (!ctx) return file

  const objectUrl = URL.createObjectURL(file)

  return new Promise((resolve) => {
    img.onload = () => {
      URL.revokeObjectURL(objectUrl)

      const originalWidth = img.width
      const originalHeight = img.height

      logImagePipeline("original", {
        preset,
        fileName: file.name,
        mimeType: file.type,
        bytes: file.size,
        width: originalWidth,
        height: originalHeight,
      })

      let width = originalWidth
      let height = originalHeight

      if (width > config.maxWidth) {
        const scale = config.maxWidth / width
        width = config.maxWidth
        height = Math.round(height * scale)
      }

      if (
        config.skipWhenWithinLimits &&
        width === originalWidth &&
        height === originalHeight
      ) {
        logImagePipeline("stored", {
          preset,
          action: "skipped-compression",
          width: originalWidth,
          height: originalHeight,
          bytes: file.size,
          mimeType: file.type,
        })
        resolve(file)
        return
      }

      canvas.width = width
      canvas.height = height

      if (config.crispDownscale) {
        ctx.imageSmoothingEnabled = false
      }

      ctx.drawImage(img, 0, 0, width, height)

      const { mime, extension } = resolveOutputType(file.type, preset)

      canvas.toBlob(
        (blob) => {
          if (!blob) {
            logImagePipeline("stored", {
              preset,
              action: "blob-failed-fallback-original",
              width: originalWidth,
              height: originalHeight,
            })
            return resolve(file)
          }

          const newName = file.name.replace(/\.[^/.]+$/, "") + `.${extension}`

          const compressed = new File([blob], newName, { type: mime })

          logImagePipeline("stored", {
            preset,
            action: "compressed",
            originalWidth,
            originalHeight,
            uploadedWidth: width,
            uploadedHeight: height,
            bytes: compressed.size,
            mimeType: mime,
          })

          resolve(compressed)
        },
        mime,
        config.quality
      )
    }

    img.onerror = () => {
      URL.revokeObjectURL(objectUrl)
      resolve(file)
    }

    img.src = objectUrl
  })
}

/** Higher-fidelity compression for trade chart screenshots. */
export async function compressScreenshot(file: File): Promise<File> {
  return compressImage(file, { preset: "screenshot" })
}

/** Log rendered dimensions when an image finishes loading (dev only). */
export function logRenderedImageDimensions(
  context: string,
  img: HTMLImageElement,
  src?: string | null
) {
  if (process.env.NODE_ENV !== "development") return

  const naturalWidth = img.naturalWidth
  const naturalHeight = img.naturalHeight
  const renderedWidth = Math.round(img.clientWidth)
  const renderedHeight = Math.round(img.clientHeight)

  logImagePipeline("rendered", {
    context,
    src: src ?? img.currentSrc ?? img.src,
    naturalWidth,
    naturalHeight,
    renderedWidth,
    renderedHeight,
    upscale:
      renderedWidth > naturalWidth || renderedHeight > naturalHeight,
  })
}
