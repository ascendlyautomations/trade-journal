/** Tradovate CashBalanceLog entity (subset used for fill-id discovery). */
export type TradovateCashBalanceLogRaw = {
  id?: number | string
  accountId?: number | string
  timestamp?: string
  fillId?: number | string | null
  fillPairId?: number | string | null
  cashChangeType?: string
  realizedPnL?: number
}

export function parseTradovateCashBalanceLogFillId(
  row: TradovateCashBalanceLogRaw
): string | null {
  const raw = row.fillId
  if (raw == null) return null
  const id = String(raw).trim()
  if (!id || id === "0") return null
  return id
}

export function filterCashBalanceLogsWithinLookback(
  rows: TradovateCashBalanceLogRaw[],
  lookbackStartIso: string
): TradovateCashBalanceLogRaw[] {
  return rows.filter((row) => {
    const ts = row.timestamp ? String(row.timestamp) : null
    if (!ts) return true
    return ts >= lookbackStartIso
  })
}

export function collectFillIdsFromCashBalanceLogs(
  rows: TradovateCashBalanceLogRaw[]
): string[] {
  const out = new Set<string>()
  for (const row of rows) {
    const fillId = parseTradovateCashBalanceLogFillId(row)
    if (fillId) out.add(fillId)
  }
  return [...out]
}
