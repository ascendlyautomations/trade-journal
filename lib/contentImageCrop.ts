/** Saved Posts / Trades crop. Same JSON iOS stores on `image_crop`. */
export type NormalizedImageCrop = {
  x: number
  y: number
  width: number
  height: number
}

export type SavedContentImageCrop = {
  presentationAspectRatio: number
  normalizedCrop: NormalizedImageCrop
}

function finiteNumber(value: unknown): number | null {
  const number = typeof value === "number" ? value : Number(value)
  return Number.isFinite(number) ? number : null
}

/** Returns the crop only when a real normalized rect was saved. */
export function parseSavedContentImageCrop(
  value: unknown
): SavedContentImageCrop | null {
  let parsed = value
  if (typeof parsed === "string") {
    try {
      parsed = JSON.parse(parsed) as unknown
    } catch {
      return null
    }
  }
  if (!parsed || typeof parsed !== "object") return null
  const row = parsed as Record<string, unknown>
  const aspect = finiteNumber(row.presentation_aspect_ratio)
  const cropRaw = row.normalized_crop
  if (aspect == null || aspect <= 0 || !cropRaw || typeof cropRaw !== "object") {
    return null
  }
  const crop = cropRaw as Record<string, unknown>
  const x = finiteNumber(crop.x)
  const y = finiteNumber(crop.y)
  const width = finiteNumber(crop.width)
  const height = finiteNumber(crop.height)
  if (
    x == null ||
    y == null ||
    width == null ||
    height == null ||
    width <= 0 ||
    height <= 0
  ) {
    return null
  }
  return {
    presentationAspectRatio: aspect,
    normalizedCrop: {
      x,
      y,
      width: Math.min(width, 1),
      height: Math.min(height, 1),
    },
  }
}
