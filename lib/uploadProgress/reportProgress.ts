import type { UploadProgressReporter } from "./types"

/** Monotonic percent clamped to 0–99 during active upload (100 reserved for success). */
export function createMonotonicReporter(
  report: UploadProgressReporter | undefined,
  range?: { min: number; max: number }
): UploadProgressReporter {
  if (!report) return () => {}

  let lastPercent = range?.min ?? 0
  const min = range?.min ?? 0
  const max = range?.max ?? 99

  return (update) => {
    const clamped = Math.max(min, Math.min(max, Math.round(update.percent)))
    lastPercent = Math.max(lastPercent, clamped)
    report({ percent: lastPercent, stage: update.stage })
  }
}

export function mapUploadBytesToPercent(
  loaded: number,
  total: number,
  range: { start: number; end: number }
): number {
  if (total <= 0) return range.start
  const ratio = Math.max(0, Math.min(1, loaded / total))
  return range.start + ratio * (range.end - range.start)
}
