/** Progressive seeks after the initial first-visible offset — never capture at t=0. */
export const THUMBNAIL_RETRY_SEEK_SECONDS = [0.1, 0.25, 0.5, 1] as const

export function clampReelSeekTime(duration: number, seekSeconds: number): number {
  if (!Number.isFinite(duration) || duration <= 0) return 0.05
  const maxSeek = Math.max(duration - 0.05, 0)
  // Never clamp to exact 0 — many encoders have a black/empty first sample.
  const minSeek = Math.min(0.05, maxSeek)
  return Math.min(Math.max(seekSeconds, minSeek), maxSeek)
}

/** Earliest seek that usually has a decoded, non-black frame. */
export function firstVisibleReelSeekTime(duration: number): number {
  if (!Number.isFinite(duration) || duration <= 0) return 0.05
  const target = Math.min(0.1, duration / 10)
  if (!Number.isFinite(target) || target <= 0) return 0.05
  return clampReelSeekTime(duration, target)
}

/** Ordered seek times for thumbnail capture (skips exact t=0). */
export function buildReelThumbnailSeekCandidates(
  duration: number,
  preferred?: number
): number[] {
  const primary = firstVisibleReelSeekTime(duration)
  const preferredClamped =
    preferred != null && preferred > 0
      ? clampReelSeekTime(duration, preferred)
      : null

  const seeds = [
    preferredClamped,
    primary,
    ...THUMBNAIL_RETRY_SEEK_SECONDS,
  ]

  const seen = new Set<string>()
  const out: number[] = []

  for (const candidate of seeds) {
    if (candidate == null) continue
    const clamped = clampReelSeekTime(duration, candidate)
    if (clamped <= 0) continue
    const key = clamped.toFixed(3)
    if (seen.has(key)) continue
    seen.add(key)
    out.push(clamped)
  }

  return out
}
