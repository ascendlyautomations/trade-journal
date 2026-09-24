import type { TradovateFillRaw } from "./tradovateFillModels.ts"
import { tradovateFillStableId } from "./tradovateFillModels.ts"
import { filterParsedTradovateFillsForAccount } from "./tradovateOrderAccountMap.ts"

export const TRADOVATE_FILL_ACQUISITION_VERSION = "fillAcquisition=v3"

/** Conservative batch size for Tradovate /ldeps masterids (matches fillFee ldeps). */
export const TRADOVATE_LDEPS_BATCH_SIZE = 40

export function tradovateLdepsBatchCount(orderIdCount: number): number {
  if (orderIdCount <= 0) return 0
  return Math.ceil(orderIdCount / TRADOVATE_LDEPS_BATCH_SIZE)
}

export type TradovateFillAcquisitionStats = {
  accountId: string
  orderDepsCount: number
  orderIdsCount: number
  fillLdepsCount: number
  fillListCount: number
  mergedUniqueFillCount: number
  earliestFillTimestamp: string | null
  latestFillTimestamp: string | null
  fillLdepsBatchErrors: number
  orderDepsFailed: boolean
  fillListFailed: boolean
  fillItemsRepairCount: number
  fillItemsRepairRequested: number
}

export function dedupeTradovateFillsById(fills: TradovateFillRaw[]): TradovateFillRaw[] {
  const byId = new Map<string, TradovateFillRaw>()
  for (const fill of fills) {
    if (fill.id == null) continue
    byId.set(tradovateFillStableId(fill), fill)
  }
  return [...byId.values()]
}

/** Primary account-scoped fills (deps path) + supplemental fill/list fills for same account. */
export function mergeAccountScopedTradovateFills(params: {
  primaryFills: TradovateFillRaw[]
  supplementalFills: TradovateFillRaw[]
  targetAccountId: string
  orderAccountById: Map<string, string>
}): TradovateFillRaw[] {
  const merged = dedupeTradovateFillsById(params.primaryFills)
  const seen = new Set(merged.map((f) => tradovateFillStableId(f)))
  const supplementalParsed = filterParsedTradovateFillsForAccount(
    params.supplementalFills,
    params.targetAccountId,
    params.orderAccountById
  )
  for (const fill of supplementalParsed) {
    const id = tradovateFillStableId(fill)
    if (seen.has(id)) continue
    seen.add(id)
    merged.push(fill)
  }
  return merged
}

export function fillTimestampWindow(fills: TradovateFillRaw[]): {
  earliestFillTimestamp: string | null
  latestFillTimestamp: string | null
} {
  let earliest: string | null = null
  let latest: string | null = null
  for (const fill of fills) {
    const ts = fill.timestamp ? String(fill.timestamp) : null
    if (!ts) continue
    if (!earliest || ts < earliest) earliest = ts
    if (!latest || ts > latest) latest = ts
  }
  return { earliestFillTimestamp: earliest, latestFillTimestamp: latest }
}

export function logTradovateFillAcquisitionSummary(params: {
  stats: TradovateFillAcquisitionStats
  newLedgerExecutions: number
  existingLedgerExecutions: number
}): void {
  const { stats } = params
  console.info(
    [
      "[TradovateFillAcquisition]",
      TRADOVATE_FILL_ACQUISITION_VERSION,
      `accountId=${stats.accountId}`,
      `orderDepsCount=${stats.orderDepsCount}`,
      `orderIdsCount=${stats.orderIdsCount}`,
      `fillLdepsCount=${stats.fillLdepsCount}`,
      `fillListCount=${stats.fillListCount}`,
      `mergedUniqueFillCount=${stats.mergedUniqueFillCount}`,
      `newLedgerExecutions=${params.newLedgerExecutions}`,
      `existingLedgerExecutions=${params.existingLedgerExecutions}`,
      `earliestFillTimestamp=${stats.earliestFillTimestamp ?? "null"}`,
      `latestFillTimestamp=${stats.latestFillTimestamp ?? "null"}`,
      `orderDepsFailed=${stats.orderDepsFailed}`,
      `fillListFailed=${stats.fillListFailed}`,
      `fillLdepsBatchErrors=${stats.fillLdepsBatchErrors}`,
      `fillItemsRepairCount=${stats.fillItemsRepairCount}`,
      `fillItemsRepairRequested=${stats.fillItemsRepairRequested}`,
    ].join(" ")
  )
}
