import type { TradovateFillRaw } from "./tradovateFillModels.ts"
import { TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS } from "./tradovatePerformanceRegressionConstants.ts"
import { fillTimestampWindow } from "./tradovateFillAcquisitionCore.ts"

/**
 * Tradovate REST acquisition semantics (official paths used by sync):
 *
 * - order/deps?masterid={accountId}: dependent orders for the account entity — **recent / session-scoped
 *   in production**, not a guaranteed full historical order archive.
 * - order/list: all orders visible to the authenticated user — **current visibility window**, not archival.
 * - order/items?ids=: point lookup by order id (repair / hydration).
 * - fill/ldeps?masterids={orderIds}: fills for those orders — bounded by which order ids were obtained.
 * - fill/list: fills visible to the user — **same recent-window limitation** as order/list in production.
 * - fill/items?ids=: point lookup by fill id — **repair path** when list/deps omit historical fills.
 * - position/deps?masterid={accountId}: open/recent positions — not historical flat archive.
 * - fillPair/ldeps / fillPair/list: validation-only; same recent-window behavior as fills/positions.
 * - user/syncrequest (WebSocket): incremental props stream — triggers sync; does not replace REST backfill.
 *
 * Therefore INITIAL BACKFILL = deps + list + ldeps + bounded fill/items repair + ledger merge.
 * INCREMENTAL = same pipeline with watermark; skip repair when coverage verified.
 * REPAIR = fill/items (+ order/items) for hole candidates without deleting ledger rows.
 */

export type TradovateLedgerAcquisitionSnapshot = {
  executionCount: number
  earliestExecutedAt: string | null
  latestExecutedAt: string | null
  fillIds: Set<string>
}

export type TradovateHistoricalCompleteness = {
  requestedStart: string | null
  requestedEnd: string | null
  retrievedEarliest: string | null
  retrievedLatest: string | null
  historicalBackfillAttempted: boolean
  historicalBackfillComplete: boolean
  incrementalWatermark: string | null
  holesDetected: string[]
  repairAttempted: boolean
  repairFillIdsRequested: string[]
  repairFillIdsRecovered: string[]
}

export function ledgerWindowFromSnapshot(
  snapshot: TradovateLedgerAcquisitionSnapshot
): { earliest: string | null; latest: string | null } {
  return {
    earliest: snapshot.earliestExecutedAt,
    latest: snapshot.latestExecutedAt,
  }
}

export function buildTradovateRepairFillIdCandidates(params: {
  mergedFillIds: Set<string>
  ledgerFillIds: Set<string>
  extraRecoveryFillIds?: readonly string[]
}): string[] {
  const recovery =
    params.extraRecoveryFillIds ?? TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS
  const out = new Set<string>()
  for (const fillId of recovery) {
    const id = String(fillId).trim()
    if (!id) continue
    if (params.mergedFillIds.has(id)) continue
    out.add(id)
  }
  return [...out]
}

export function assessTradovateHistoricalCompleteness(params: {
  ledger: TradovateLedgerAcquisitionSnapshot
  accountFills: TradovateFillRaw[]
  incrementalWatermark: string | null
  repairAttempted: boolean
  repairFillIdsRequested: string[]
  repairFillIdsRecovered: string[]
  /** When set (initial backfill), remote window must cover this start. */
  requestedStart?: string | null
  requestedEnd?: string | null
}): TradovateHistoricalCompleteness {
  const window = fillTimestampWindow(params.accountFills)
  const holes: string[] = []

  for (const fillId of TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS) {
    if (
      !params.ledger.fillIds.has(fillId) &&
      !params.accountFills.some((f) => String(f.id) === fillId)
    ) {
      holes.push(fillId)
    }
  }

  if (
    params.ledger.executionCount > 0 &&
    params.ledger.earliestExecutedAt &&
    window.earliestFillTimestamp &&
    window.earliestFillTimestamp > params.ledger.earliestExecutedAt
  ) {
    holes.push(
      `retrieved_window_starts_after_ledger:${window.earliestFillTimestamp}>${params.ledger.earliestExecutedAt}`
    )
  }

  if (
    params.ledger.executionCount > params.accountFills.length &&
    params.accountFills.length > 0 &&
    params.ledger.executionCount >= 5
  ) {
    holes.push(
      `remote_fill_count_below_ledger:${params.accountFills.length}<${params.ledger.executionCount}`
    )
  }

  const historicalBackfillAttempted =
    params.repairAttempted || params.repairFillIdsRequested.length > 0

  const historicalBackfillComplete =
    holes.length === 0 &&
    !(
      params.ledger.executionCount > 0 &&
      window.earliestFillTimestamp &&
      params.ledger.earliestExecutedAt &&
      window.earliestFillTimestamp > params.ledger.earliestExecutedAt
    )

  return {
    requestedStart: params.requestedStart ?? params.ledger.earliestExecutedAt,
    requestedEnd: params.requestedEnd ?? new Date().toISOString(),
    retrievedEarliest: window.earliestFillTimestamp,
    retrievedLatest: window.latestFillTimestamp,
    historicalBackfillAttempted,
    historicalBackfillComplete,
    incrementalWatermark: params.incrementalWatermark,
    holesDetected: holes,
    repairAttempted: params.repairAttempted,
    repairFillIdsRequested: params.repairFillIdsRequested,
    repairFillIdsRecovered: params.repairFillIdsRecovered,
  }
}

export function logTradovateHistoricalCompleteness(
  completeness: TradovateHistoricalCompleteness
): void {
  console.info(
    [
      "[TradovateHistoricalCompleteness]",
      `requestedStart=${completeness.requestedStart ?? "null"}`,
      `requestedEnd=${completeness.requestedEnd ?? "null"}`,
      `retrievedEarliest=${completeness.retrievedEarliest ?? "null"}`,
      `retrievedLatest=${completeness.retrievedLatest ?? "null"}`,
      `historicalBackfillAttempted=${completeness.historicalBackfillAttempted}`,
      `historicalBackfillComplete=${completeness.historicalBackfillComplete}`,
      `incrementalWatermark=${completeness.incrementalWatermark ?? "null"}`,
      `holesDetected=${completeness.holesDetected.length}`,
      `repairAttempted=${completeness.repairAttempted}`,
      `repairRecovered=${completeness.repairFillIdsRecovered.length}`,
    ].join(" ")
  )
  if (completeness.holesDetected.length > 0) {
    console.info(
      `[TradovateHistoricalCompleteness] holes=${completeness.holesDetected.join("|")}`
    )
  }
}
