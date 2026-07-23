import { isNativePlatform } from "./nativePlatform"

/**
 * Centralized sharing (Phase 2B).
 *
 * Native iOS → Capacitor Share plugin (system UIActivityViewController).
 * Web → existing browser behavior (download for images/files, Web Share API
 * for URLs when available). Call sites never branch on platform.
 *
 * Filesystem + Share are dynamic-imported only when sharing on native so they
 * are not part of the cold-start JS graph.
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

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(reader.error ?? new Error("read failed"))
    reader.onload = () => {
      const result = String(reader.result || "")
      const comma = result.indexOf(",")
      resolve(comma >= 0 ? result.slice(comma + 1) : result)
    }
    reader.readAsDataURL(blob)
  })
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

async function shareFileNative(
  file: File,
  options: ShareMediaOptions
): Promise<ShareOutcome> {
  const [{ Directory, Filesystem }, { Share }] = await Promise.all([
    import("@capacitor/filesystem"),
    import("@capacitor/share"),
  ])

  const path = `share/${Date.now()}-${file.name.replace(/[^\w.-]+/g, "_")}`
  const base64 = await blobToBase64(file)

  await Filesystem.writeFile({
    path,
    data: base64,
    directory: Directory.Cache,
  })

  const { uri } = await Filesystem.getUri({
    path,
    directory: Directory.Cache,
  })

  try {
    await Share.share({
      title: options.title,
      text: options.text,
      files: [uri],
      dialogTitle: options.title,
    })
    return { ok: true, cancelled: false }
  } catch (error) {
    // User dismissed the sheet — not an application error.
    if ((error as { message?: string })?.message?.toLowerCase().includes("cancel") ||
        (error as DOMException)?.name === "AbortError") {
      return { ok: false, cancelled: true }
    }
    // Some iOS dismissals throw a generic CapacitorException with no AbortError.
    const message = String((error as { message?: string })?.message || error || "")
    if (/cancel|dismiss|abort/i.test(message)) {
      return { ok: false, cancelled: true }
    }
    throw error
  } finally {
    try {
      await Filesystem.deleteFile({ path, directory: Directory.Cache })
    } catch {
      // Cache cleanup is best-effort.
    }
  }
}

/**
 * Share an image (File, Blob, data URL / http URL, or canvas).
 * Native → system Share Sheet. Web → browser download (unchanged).
 */
export async function shareImage(
  input: File | Blob | string | HTMLCanvasElement,
  options: ShareMediaOptions = {}
): Promise<ShareOutcome> {
  const file = await normalizeToFile(input, options.filename)
  if (!isNativePlatform()) {
    downloadInBrowser(file)
    return { ok: true, cancelled: false }
  }
  return shareFileNative(file, options)
}

/**
 * Share any file (File, Blob, or URL string that resolves to binary).
 * Native → system Share Sheet. Web → browser download (unchanged).
 */
export async function shareFile(
  input: File | Blob | string,
  options: ShareMediaOptions = {}
): Promise<ShareOutcome> {
  const file = await normalizeToFile(input, options.filename)
  if (!isNativePlatform()) {
    downloadInBrowser(file)
    return { ok: true, cancelled: false }
  }
  return shareFileNative(file, options)
}

/**
 * Share a link / text. Native → Share Sheet. Web → navigator.share when
 * available; returns cancelled/false so the caller can fall back to clipboard
 * (preserves existing TraxsProForLifeCard behavior).
 */
export async function shareUrl(
  options: ShareLinkOptions
): Promise<ShareOutcome> {
  if (isNativePlatform()) {
    try {
      const { Share } = await import("@capacitor/share")
      await Share.share({
        title: options.title,
        text: options.text,
        url: options.url,
        dialogTitle: options.title,
      })
      return { ok: true, cancelled: false }
    } catch (error) {
      const message = String((error as { message?: string })?.message || error || "")
      if (
        (error as DOMException)?.name === "AbortError" ||
        /cancel|dismiss|abort/i.test(message)
      ) {
        return { ok: false, cancelled: true }
      }
      throw error
    }
  }

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
