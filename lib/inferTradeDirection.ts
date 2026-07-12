/** Canonical trade direction values used by manual entry, Quick Input, and CSV import. */
export type TradeDirection = "Long" | "Short"

export function parseTradePriceInput(raw: string): number | null {
  if (!raw.trim()) return null
  const n = Number(raw.replace(/,/g, "").replace(/\$/g, ""))
  return Number.isFinite(n) ? n : null
}

/**
 * Infer Long/Short from entry vs exit price only.
 * Returns null when either price is missing/invalid or prices are equal
 * (do not overwrite an existing selection).
 */
export function inferTradeDirectionFromPrices(
  entryPrice: number | null | undefined,
  exitPrice: number | null | undefined
): TradeDirection | null {
  if (
    entryPrice == null ||
    exitPrice == null ||
    !Number.isFinite(entryPrice) ||
    !Number.isFinite(exitPrice)
  ) {
    return null
  }
  if (exitPrice > entryPrice) return "Long"
  if (exitPrice < entryPrice) return "Short"
  return null
}

/** Resolve direction after entry/exit edits, respecting a user manual override. */
export function nextDirectionAfterPriceChange(options: {
  current: TradeDirection
  manualOverride: boolean
  entryPrice: number | null | undefined
  exitPrice: number | null | undefined
}): TradeDirection {
  if (options.manualOverride) return options.current
  return (
    inferTradeDirectionFromPrices(options.entryPrice, options.exitPrice) ??
    options.current
  )
}
