import type { ReconstructionFill } from "@/lib/integrations/tradovate/tradeReconstruction"

export type RithmicFillHistoryRow = {
  fillId: string
  fcmId: string
  ibId: string
  accountId: string
  symbol: string
  exchange: string
  side: "Buy" | "Sell"
  quantity: number
  price: number
  executedAt: string
  ssboe: number | null
  usecs: number | null
  sequenceNumber: string | null
  rawSymbol: string
  transactionTypeRaw: string | null
}

export function parseRithmicExternalAccountParts(externalAccountId: string): {
  fcmId: string
  ibId: string
  accountId: string
} | null {
  const parts = externalAccountId.split("|")
  if (parts.length !== 3) return null
  const [fcmId, ibId, accountId] = parts
  if (!fcmId || !ibId || !accountId) return null
  return { fcmId, ibId, accountId }
}

export function rithmicInstrumentKey(exchange: string, symbol: string): string {
  return `${exchange}:${symbol}`.toUpperCase()
}

/** Best-effort symbol root for TradeTraxs ticker (preserve raw separately). */
export function normalizeRithmicSymbolRoot(symbol: string): string {
  const s = symbol.trim().toUpperCase()
  if (!s) return symbol
  const monthCode = /[FGHJKMNQUVXZ]\d{1,2}$/
  const withoutMonth = s.replace(monthCode, "")
  return withoutMonth || s
}

export function rithmicSideFromTransactionType(raw: string | number | null | undefined): "Buy" | "Sell" | null {
  if (raw == null) return null
  if (typeof raw === "number") {
    if (raw === 1) return "Buy"
    if (raw === 2) return "Sell"
    return null
  }
  const v = raw.trim().toUpperCase()
  if (v === "1" || v === "BUY") return "Buy"
  if (v === "2" || v === "SELL") return "Sell"
  return null
}

export function rithmicExecutedAtFromSsboe(ssboe: number | null, usecs: number | null): string | null {
  if (ssboe == null || !Number.isFinite(ssboe)) return null
  const ms = ssboe * 1000 + Math.floor((usecs ?? 0) / 1000)
  return new Date(ms).toISOString()
}

export function stableRithmicFillId(row: {
  fcmId: string
  ibId: string
  accountId: string
  fillId: string
}): string {
  return `${row.fcmId}|${row.ibId}|${row.accountId}|${row.fillId}`
}

export function toReconstructionFill(row: RithmicFillHistoryRow): ReconstructionFill | null {
  if (!row.fillId || row.quantity <= 0) return null
  return {
    fillId: stableRithmicFillId(row),
    contractId: rithmicInstrumentKey(row.exchange, row.symbol),
    timestamp: row.executedAt,
    action: row.side,
    qty: row.quantity,
    price: row.price,
  }
}

export type RithmicFillCheckpoint = {
  indexFormat: "ssboe"
  lastSsboe: number
  lastUsecs: number
}

export function readRithmicFillCheckpoint(
  providerSyncState: Record<string, unknown> | null | undefined
): RithmicFillCheckpoint | null {
  const rithmic = providerSyncState?.rithmic
  if (!rithmic || typeof rithmic !== "object") return null
  const o = rithmic as Record<string, unknown>
  if (o.indexFormat !== "ssboe") return null
  const lastSsboe = Number(o.lastSsboe)
  const lastUsecs = Number(o.lastUsecs ?? 0)
  if (!Number.isFinite(lastSsboe)) return null
  return { indexFormat: "ssboe", lastSsboe, lastUsecs }
}

export function mergeRithmicFillCheckpoint(
  providerSyncState: Record<string, unknown> | null | undefined,
  checkpoint: RithmicFillCheckpoint
): Record<string, unknown> {
  return {
    ...(providerSyncState ?? {}),
    rithmic: checkpoint,
  }
}
