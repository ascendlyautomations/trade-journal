/** Layout constants for performance share PNG export (no html-to-image dependency). */

export const PERFORMANCE_SHARE_EXPORT_WIDTH = 520

export const PERFORMANCE_SHARE_EXPORT_MIN_HEIGHT = 720

export type CaptureShareCardOptions = {
  /** Extra wait for Recharts/SVG layout (ms). */
  warmupMs?: number
  /** Label for console logging. */
  logContext?: string
}
