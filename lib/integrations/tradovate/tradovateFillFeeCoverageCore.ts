import type { TradovateFillFeeRaw } from "./tradovateFillModels.ts"

export type TradovateFillFeeTotals = {
  clearingFee: number
  exchangeFee: number
  nfaFee: number
  commission: number
}

export type TradovateFillFeeAvailability = "KNOWN_VALUE" | "KNOWN_ZERO" | "UNAVAILABLE"

export type TradovateFillFeeRecord = {
  totals: TradovateFillFeeTotals
  availability: TradovateFillFeeAvailability
}

export function emptyTradovateFillFeeTotals(): TradovateFillFeeTotals {
  return { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 }
}

export function sumTradovateFillFeeTotals(t: TradovateFillFeeTotals): number {
  return t.clearingFee + t.exchangeFee + t.nfaFee + t.commission
}

export function totalsFromTradovateFillFeeRaw(fee: TradovateFillFeeRaw): TradovateFillFeeTotals {
  return {
    clearingFee: Number(fee.clearingFee ?? 0) || 0,
    exchangeFee: Number(fee.exchangeFee ?? 0) || 0,
    nfaFee: Number(fee.nfaFee ?? 0) || 0,
    commission: Number(fee.commission ?? 0) || 0,
  }
}

export function fillFeeAvailabilityFromTotals(
  totals: TradovateFillFeeTotals
): TradovateFillFeeAvailability {
  return sumTradovateFillFeeTotals(totals) === 0 ? "KNOWN_ZERO" : "KNOWN_VALUE"
}

export function mergeTradovateFillFeeRecords(
  existing: TradovateFillFeeRecord | null | undefined,
  incoming: TradovateFillFeeRecord | null | undefined
): TradovateFillFeeRecord {
  if (!existing && !incoming) {
    return { totals: emptyTradovateFillFeeTotals(), availability: "UNAVAILABLE" }
  }
  if (!incoming) return existing!
  if (!existing) return incoming

  if (existing.availability !== "UNAVAILABLE" && incoming.availability === "UNAVAILABLE") {
    return existing
  }
  if (incoming.availability === "UNAVAILABLE") {
    return existing.availability === "UNAVAILABLE" ? incoming : existing
  }

  return incoming
}

export function mergeTradovateFillFeeMaps(
  persisted: Map<string, TradovateFillFeeRecord>,
  fetched: Map<string, TradovateFillFeeRecord>
): Map<string, TradovateFillFeeRecord> {
  const out = new Map(persisted)
  for (const [fillId, incoming] of fetched) {
    out.set(fillId, mergeTradovateFillFeeRecords(out.get(fillId), incoming))
  }
  return out
}

export function tradovateFillFeeMapToLegacyTotals(
  fees: Map<string, TradovateFillFeeRecord>
): Map<string, TradovateFillFeeTotals> {
  const out = new Map<string, TradovateFillFeeTotals>()
  for (const [fillId, record] of fees) {
    if (record.availability === "UNAVAILABLE") continue
    out.set(fillId, record.totals)
  }
  return out
}

export function sumLifecycleFeesWithAvailability(
  fees: Map<string, TradovateFillFeeRecord>,
  fillIds: string[]
): { fees: number; hasUnavailable: boolean } {
  let total = 0
  let hasUnavailable = false
  for (const id of fillIds) {
    const row = fees.get(id)
    if (!row) {
      hasUnavailable = true
      continue
    }
    if (row.availability === "UNAVAILABLE") {
      hasUnavailable = true
      continue
    }
    total += sumTradovateFillFeeTotals(row.totals)
  }
  return { fees: total, hasUnavailable }
}
