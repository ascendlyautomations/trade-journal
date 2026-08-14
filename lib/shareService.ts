/**
 * Centralized sharing.
 *
 * Web → browser download for images/files, Web Share API for URLs when available.
 * Capacitor Share / Filesystem plugins removed (Swift owns native share).
 */

export type ShareMediaOptions = {
  /** Suggested filename, e.g. trade-AAPL-….png */
  filename?: string
  title?: string
  text?: string
}

export type ShareLinkOptions = {
  title?: string
  text?: string
  url: string
}

export type ShareOutcome = {
  /** True when content was handed to the OS share sheet / download completed. */
  ok: boolean
  /** True when the user dismissed the native sheet without sharing. */
  cancelled: boolean
}

function extensionForMime(mime: string): string {
  if (mime.includes("jpeg") || mime.includes("jpg")) return "jpg"
  if (mime.includes("png")) return "png"
  if (mime.includes("webp")) return "webp"
  if (mime.includes("gif")) return "gif"
  return "bin"
}

async function canvasToBlob(canvas: HTMLCanvasElement): Promise<Blob> {
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob((b) => resolve(b), "image/png")
  )
  if (!blob) throw new Error("Could not export canvas.")
  return blob
}

async function normalizeToFile(
  input: File | Blob | string | HTMLCanvasElement,
  filename?: string
): Promise<File> {
  if (typeof HTMLCanvasElement !== "undefined" && input instanceof HTMLCanvasElement) {
    const blob = await canvasToBlob(input)
    return new File([blob], filename || `image-${Date.now()}.png`, {
      type: blob.type || "image/png",
    })
  }

  if (typeof input === "string") {
    const response = await fetch(input)
    const blob = await response.blob()
    const mime = blob.type || "application/octet-stream"
    const name =
      filename ||
      `share-${Date.now()}.${extensionForMime(mime)}`
    return new File([blob], name, { type: mime })
  }

  if (input instanceof File) {
    if (filename && filename !== input.name) {
      return new File([input], filename, {
        type: input.type || "application/octet-stream",
      })
    }
    return input
  }

  const blob = input
  const mime = blob.type || "application/octet-stream"
  return new File([blob], filename || `share-${Date.now()}.${extensionForMime(mime)}`, {
    type: mime,
  })
}

function downloadInBrowser(file: File): void {
  const url = URL.createObjectURL(file)
  const link = document.createElement("a")
  link.href = url
  link.download = file.name
  link.click()
  URL.revokeObjectURL(url)
}

/**
 * Share an image (File, Blob, data URL / http URL, or canvas).
 * Always uses browser download (Capacitor Share removed).
 */
export async function shareImage(
  input: File | Blob | string | HTMLCanvasElement,
  options: ShareMediaOptions = {}
): Promise<ShareOutcome> {
  const file = await normalizeToFile(input, options.filename)
  downloadInBrowser(file)
  return { ok: true, cancelled: false }
}

/**
 * Share any file (File, Blob, or URL string that resolves to binary).
 * Always uses browser download (Capacitor Share removed).
 */
export async function shareFile(
  input: File | Blob | string,
  options: ShareMediaOptions = {}
): Promise<ShareOutcome> {
  const file = await normalizeToFile(input, options.filename)
  downloadInBrowser(file)
  return { ok: true, cancelled: false }
}

/**
 * Share a link / text. Web Share API when available; otherwise cancelled/false
 * so the caller can fall back to clipboard.
 */
export async function shareUrl(
  options: ShareLinkOptions
): Promise<ShareOutcome> {
  if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
    try {
      await navigator.share({
        title: options.title,
        text: options.text,
        url: options.url,
      })
      return { ok: true, cancelled: false }
    } catch (error) {
      if ((error as DOMException)?.name === "AbortError") {
        return { ok: false, cancelled: true }
      }
      throw error
    }
  }

  return { ok: false, cancelled: false }
}
