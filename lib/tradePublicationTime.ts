/** Public feed publication instant (`trades.first_published_at`), not row `created_at`. */
export function tradeFirstPublishedAt(trade: {
  first_published_at?: string | null
}): string | null {
  const raw = trade.first_published_at
  if (raw == null) return null
  const trimmed = String(raw).trim()
  return trimmed.length > 0 ? trimmed : null
}