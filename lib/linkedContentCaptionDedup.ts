/** Display-only: normalize captions/notes for duplicate detection in clip + linked-trade UI. */

export function normalizeCaptionForComparison(raw: unknown): string | null {
  if (raw == null) return null
  const trimmed = String(raw).trim()
  if (!trimmed) return null
  return trimmed
    .split(/\s+/)
    .filter(Boolean)
    .join(" ")
}

export function linkedContentCaptionsEquivalent(
  a: unknown,
  b: unknown
): boolean {
  const left = normalizeCaptionForComparison(a)
  const right = normalizeCaptionForComparison(b)
  if (!left || !right) return false
  return left === right
}

export function linkedTradeDescriptionForDedup(trade: {
  public_description?: unknown
  notes?: unknown
  note_preview?: unknown
} | null | undefined): string | null {
  if (!trade) return null
  return (
    normalizeCaptionForComparison(trade.public_description) ??
    normalizeCaptionForComparison(trade.notes) ??
    normalizeCaptionForComparison(trade.note_preview)
  )
}

export function shouldHideLinkedTradeDescription(
  displayedClipCaption: unknown,
  trade: {
    public_description?: unknown
    notes?: unknown
    note_preview?: unknown
  } | null | undefined
): boolean {
  const tradeText = linkedTradeDescriptionForDedup(trade)
  if (!tradeText) return false
  return linkedContentCaptionsEquivalent(displayedClipCaption, tradeText)
}
