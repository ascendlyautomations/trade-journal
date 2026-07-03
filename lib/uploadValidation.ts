/** Client-side upload guards — size + MIME before storage upload. */

export const UPLOAD_MAX_IMAGE_BYTES = 15 * 1024 * 1024
export const UPLOAD_MAX_CSV_BYTES = 10 * 1024 * 1024

const ALLOWED_IMAGE_MIME_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
])

const ALLOWED_IMAGE_EXTENSIONS = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".webp",
  ".gif",
])

function fileExtension(name: string): string {
  const idx = name.lastIndexOf(".")
  if (idx < 0) return ""
  return name.slice(idx).toLowerCase()
}

export function validateImageUpload(file: File): string | null {
  if (!file || file.size === 0) {
    return "File is empty."
  }

  if (file.size > UPLOAD_MAX_IMAGE_BYTES) {
    const maxMb = Math.round(UPLOAD_MAX_IMAGE_BYTES / (1024 * 1024))
    return `Image must be ${maxMb} MB or smaller.`
  }

  const mime = file.type?.toLowerCase() ?? ""
  if (mime && ALLOWED_IMAGE_MIME_TYPES.has(mime)) {
    return null
  }

  const ext = fileExtension(file.name)
  if (ALLOWED_IMAGE_EXTENSIONS.has(ext)) {
    return null
  }

  if (mime.startsWith("image/")) {
    return "Unsupported image format. Use JPEG, PNG, WebP, or GIF."
  }

  return "File must be an image (JPEG, PNG, WebP, or GIF)."
}

export function validateCsvUpload(file: File): string | null {
  if (!file || file.size === 0) {
    return "File is empty."
  }

  if (file.size > UPLOAD_MAX_CSV_BYTES) {
    return "CSV file must be 10 MB or smaller."
  }

  const name = file.name.toLowerCase()
  const mime = file.type?.toLowerCase() ?? ""
  if (
    name.endsWith(".csv") ||
    mime === "text/csv" ||
    mime === "application/csv" ||
    mime === "text/plain" ||
    mime === "application/vnd.ms-excel"
  ) {
    return null
  }

  return "File must be a CSV."
}
