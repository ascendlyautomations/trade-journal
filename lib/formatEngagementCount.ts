/** Compact display for like/comment counts (social-style). */
export function formatEngagementCount(value: number): string {
  const n = Math.max(0, Math.floor(Number(value) || 0))

  if (n < 1000) return String(n)

  if (n < 10_000) {
    const k = Math.round((n / 1000) * 10) / 10
    return Number.isInteger(k) ? `${k}K` : `${k.toFixed(1)}K`
  }

  if (n < 1_000_000) {
    return `${Math.floor(n / 1000)}K`
  }

  const m = Math.round((n / 1_000_000) * 10) / 10
  return Number.isInteger(m) ? `${m}M` : `${m.toFixed(1)}M`
}

/** Full count for aria-labels and tooltips when display is abbreviated. */
export function formatEngagementCountAccessible(value: number): string {
  const n = Math.max(0, Math.floor(Number(value) || 0))
  return n.toLocaleString()
}
