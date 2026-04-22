/**
 * Browser-only: resize wide images and encode as JPEG for smaller uploads.
 * Call only from client components / client-side handlers.
 */
export async function compressImage(file: File): Promise<Blob> {
  const img = document.createElement("img")
  const canvas = document.createElement("canvas")
  const ctx = canvas.getContext("2d")

  if (!ctx) {
    return Promise.reject(new Error("Canvas 2D context unavailable"))
  }

  const objectUrl = URL.createObjectURL(file)

  return new Promise((resolve, reject) => {
    img.onload = () => {
      URL.revokeObjectURL(objectUrl)

      const MAX_WIDTH = 1200

      let width = img.width
      let height = img.height

      if (width > MAX_WIDTH) {
        const scale = MAX_WIDTH / width
        width = MAX_WIDTH
        height = height * scale
      }

      canvas.width = width
      canvas.height = height

      ctx.drawImage(img, 0, 0, width, height)

      canvas.toBlob(
        (blob) => {
          if (!blob) return reject(new Error("Compression failed"))
          resolve(blob)
        },
        "image/jpeg",
        0.7
      )
    }

    img.onerror = () => {
      URL.revokeObjectURL(objectUrl)
      reject(new Error("Failed to decode image"))
    }

    img.src = objectUrl
  })
}
