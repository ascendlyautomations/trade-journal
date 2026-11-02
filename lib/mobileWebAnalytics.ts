/** Phone-only analytics chart presentation. Desktop Recharts stay unchanged. */
export const MOBILE_WEB_CHART = {
  equityHeight: 256,
  weekdayHeight: 176,
  propFirmHeight: 200,
  tickSize: 10,
  yAxisWidth: 44,
  equityMargin: { top: 6, right: 4, left: 0, bottom: 2 },
  weekdayMargin: { top: 4, right: 6, left: 0, bottom: 0 },
} as const

export function formatMobileWebChartAxisUsd(value: number): string {
  if (!Number.isFinite(value)) return "—"
  const abs = Math.abs(value)
  const sign = value < 0 ? "-" : ""
  if (abs >= 10_000) return `${sign}$${Math.round(abs / 1000)}k`
  if (abs >= 1000) {
    const k = abs / 1000
    const text = k >= 10 ? String(Math.round(k)) : k.toFixed(1).replace(/\.0$/, "")
    return `${sign}$${text}k`
  }
  return `${sign}$${Math.round(abs)}`
}
