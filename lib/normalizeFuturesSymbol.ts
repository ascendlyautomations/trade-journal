/**
 * Normalize common futures contract symbols to root tickers.
 * Examples:
 * - MNQM6 -> MNQ
 * - NQZ25 -> NQ
 * - MGCM6 -> MGC
 * - AAPL -> AAPL (unchanged)
 */
export function normalizeFuturesSymbol(rawSymbol: string | null | undefined): string {
  if (rawSymbol == null) return ""
  const s = String(rawSymbol).trim().toUpperCase()
  if (!s) return ""

  // Futures month codes: F G H J K M N Q U V X Z
  // Contract suffix examples: M6, U6, Z25
  const withSuffix = /^([A-Z0-9]{1,6}?)([FGHJKMNQUVXZ])(\d{1,2})$/.exec(s)
  if (withSuffix) return withSuffix[1]

  return s
}

