import type { SupabaseClient } from "@supabase/supabase-js"
import { TradovateApiError } from "./tradovateApiClient.ts"
import type { TradovateFillRaw, TradovateOrderRaw } from "./tradovateFillModels.ts"
import {
  parseTradovateFillRow,
  tradovateFillStableId,
} from "./tradovateFillModels.ts"
import {
  fetchTradovateFillList,
  fetchTradovateFillsByIds,
  fetchTradovateFillsByOrderIdsLdeps,
  fetchTradovateOrderList,
  fetchTradovateOrdersByAccountDeps,
  fetchTradovateOrdersByIds,
} from "./tradovateMarketDataClient.ts"
import {
  assessTradovateHistoricalCompleteness,
  buildTradovateRepairFillIdCandidates,
  logTradovateHistoricalCompleteness,
  type TradovateHistoricalCompleteness,
  type TradovateLedgerAcquisitionSnapshot,
} from "./tradovateHistoricalAcquisitionCore.ts"
import { traceTradovateMergedAcquisitionStage } from "./tradovateFillTrace.ts"
import {
  buildTradovateOrderAccountMap,
  mergeTradovateOrderAccountMap,
  missingOrderIdsForTradovateFills,
} from "./tradovateOrderAccountMap.ts"
import { logTradovateSync } from "./tradovateSyncLogger.ts"
import {
  dedupeTradovateFillsById,
  fillTimestampWindow,
  mergeAccountScopedTradovateFills,
  type TradovateFillAcquisitionStats,
} from "./tradovateFillAcquisitionCore.ts"

export {
  TRADOVATE_FILL_ACQUISITION_VERSION,
  TRADOVATE_LDEPS_BATCH_SIZE,
  tradovateLdepsBatchCount,
  dedupeTradovateFillsById,
  mergeAccountScopedTradovateFills,
  logTradovateFillAcquisitionSummary,
  type TradovateFillAcquisitionStats,
} from "./tradovateFillAcquisitionCore.ts"

export type TradovateFillAcquisitionResult = {
  accountFills: TradovateFillRaw[]
  orderAccountById: Map<string, string>
  stats: TradovateFillAcquisitionStats
  acquisitionErrors: string[]
  historicalCompleteness: TradovateHistoricalCompleteness
  /** For fill/trace diagnostics (supplemental path). */
  supplementalFillList: TradovateFillRaw[]
  ordersFromDeps: TradovateOrderRaw[]
  ordersFromList: TradovateOrderRaw[]
  fillsFromItemsRepair: TradovateFillRaw[]
}

/**
 * Account-scoped fill acquisition:
 * order/deps(account) → fill/ldeps(orders) + supplemental fill/list (account-filtered).
 */
export async function acquireTradovateFillsForAccount(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    targetAccountId: string
    mappingId: string
    trigger: string
    ledgerSnapshot?: TradovateLedgerAcquisitionSnapshot
    incrementalWatermark?: string | null
  }
): Promise<TradovateFillAcquisitionResult> {
  const ledgerSnapshot = params.ledgerSnapshot ?? {
    executionCount: 0,
    earliestExecutedAt: null,
    latestExecutedAt: null,
    fillIds: new Set<string>(),
  }
  const acquisitionErrors: string[] = []
  let orderDepsFailed = false
  let fillListFailed = false
  let fillLdepsBatchErrors = 0

  let ordersFromDeps: TradovateOrderRaw[] = []
  try {
    ordersFromDeps = await fetchTradovateOrdersByAccountDeps(
      supabase,
      params.userId,
      params.connectionId,
      params.targetAccountId
    )
  } catch (err) {
    orderDepsFailed = true
    const detail =
      err instanceof TradovateApiError
        ? `${err.code}:${err.message}`
        : err instanceof Error
          ? err.message
          : "order_deps_failed"
    acquisitionErrors.push(`order_deps:${detail}`)
    logTradovateSync("sync_error", {
      userId: params.userId,
      connectionId: params.connectionId,
      mappingId: params.mappingId,
      trigger: params.trigger,
      failureCategory: "order_retrieval_failure",
      failureStage: "order_deps",
      errorCode: "order_deps_failed",
      detail: detail.slice(0, 200),
    })
  }

  const orderIdsFromDeps = [
    ...new Set(
      ordersFromDeps
        .filter((o) => o.id != null)
        .map((o) => String(o.id))
    ),
  ]

  let fillsFromLdeps: TradovateFillRaw[] = []
  if (orderIdsFromDeps.length > 0) {
    const ldeps = await fetchTradovateFillsByOrderIdsLdeps(
      supabase,
      params.userId,
      params.connectionId,
      orderIdsFromDeps
    )
    fillsFromLdeps = ldeps.fills
    fillLdepsBatchErrors = ldeps.batchErrors.length
    for (const batchErr of ldeps.batchErrors) {
      acquisitionErrors.push(`fill_ldeps:${batchErr}`)
      logTradovateSync("sync_error", {
        userId: params.userId,
        connectionId: params.connectionId,
        mappingId: params.mappingId,
        trigger: params.trigger,
        failureCategory: "fill_retrieval_failure",
        failureStage: "fill_ldeps",
        errorCode: "fill_ldeps_batch_failed",
        detail: batchErr.slice(0, 200),
      })
    }
  }

  let fillsFromList: TradovateFillRaw[] = []
  let ordersFromList: TradovateOrderRaw[] = []
  try {
    fillsFromList = await fetchTradovateFillList(
      supabase,
      params.userId,
      params.connectionId
    )
  } catch (err) {
    fillListFailed = true
    const detail =
      err instanceof TradovateApiError
        ? `${err.code}:${err.message}`
        : err instanceof Error
          ? err.message
          : "fill_list_failed"
    acquisitionErrors.push(`fill_list:${detail}`)
    logTradovateSync("sync_error", {
      userId: params.userId,
      connectionId: params.connectionId,
      mappingId: params.mappingId,
      trigger: params.trigger,
      failureCategory: "fill_retrieval_failure",
      failureStage: "fill_list",
      errorCode: "fill_list_failed",
      detail: detail.slice(0, 200),
    })
  }

  try {
    ordersFromList = await fetchTradovateOrderList(
      supabase,
      params.userId,
      params.connectionId
    )
  } catch (err) {
    const detail =
      err instanceof TradovateApiError
        ? `${err.code}:${err.message}`
        : err instanceof Error
          ? err.message
          : "order_list_failed"
    acquisitionErrors.push(`order_list:${detail}`)
    logTradovateSync("sync_error", {
      userId: params.userId,
      connectionId: params.connectionId,
      mappingId: params.mappingId,
      trigger: params.trigger,
      failureCategory: "order_retrieval_failure",
      failureStage: "order_list",
      errorCode: "order_list_failed",
      detail: detail.slice(0, 200),
    })
  }

  const orderAccountById = buildTradovateOrderAccountMap([
    ...ordersFromDeps,
    ...ordersFromList,
  ])
  for (const order of ordersFromDeps) {
    if (order.id == null) continue
    orderAccountById.set(String(order.id), params.targetAccountId)
  }

  const missingOrderIds = missingOrderIdsForTradovateFills(fillsFromList, orderAccountById)
  if (missingOrderIds.length > 0) {
    try {
      const hydrated = await fetchTradovateOrdersByIds(
        supabase,
        params.userId,
        params.connectionId,
        missingOrderIds
      )
      mergeTradovateOrderAccountMap(orderAccountById, hydrated)
    } catch (err) {
      const detail =
        err instanceof Error ? err.message.slice(0, 120) : "order_items_failed"
      acquisitionErrors.push(`order_items:${detail}`)
    }
  }

  const primaryFills = dedupeTradovateFillsById(fillsFromLdeps).filter((row) =>
    Boolean(parseTradovateFillRow(row))
  )

  let accountFills = mergeAccountScopedTradovateFills({
    primaryFills,
    supplementalFills: fillsFromList,
    targetAccountId: params.targetAccountId,
    orderAccountById,
  })

  const mergedBeforeRepair = new Set(
    accountFills.map((f) => tradovateFillStableId(f))
  )
  const repairCandidates = buildTradovateRepairFillIdCandidates({
    mergedFillIds: mergedBeforeRepair,
    ledgerFillIds: ledgerSnapshot.fillIds,
  })
  let fillsFromItemsRepair: TradovateFillRaw[] = []
  let repairAttempted = false
  if (repairCandidates.length > 0) {
    repairAttempted = true
    try {
      fillsFromItemsRepair = await fetchTradovateFillsByIds(
        supabase,
        params.userId,
        params.connectionId,
        repairCandidates
      )
    } catch (err) {
      const detail =
        err instanceof TradovateApiError
          ? `${err.code}:${err.message}`
          : err instanceof Error
            ? err.message
            : "fill_items_failed"
      acquisitionErrors.push(`fill_items_repair:${detail}`)
    }

    const repairOrderIds = [
      ...new Set(
        fillsFromItemsRepair
          .filter((f) => f.orderId != null)
          .map((f) => String(f.orderId))
      ),
    ].filter((id) => !orderAccountById.has(id))
    if (repairOrderIds.length > 0) {
      try {
        const hydrated = await fetchTradovateOrdersByIds(
          supabase,
          params.userId,
          params.connectionId,
          repairOrderIds
        )
        mergeTradovateOrderAccountMap(orderAccountById, hydrated)
      } catch (err) {
        const detail =
          err instanceof Error ? err.message.slice(0, 120) : "order_items_repair_failed"
        acquisitionErrors.push(`order_items_repair:${detail}`)
      }
    }

    accountFills = mergeAccountScopedTradovateFills({
      primaryFills: accountFills,
      supplementalFills: fillsFromItemsRepair,
      targetAccountId: params.targetAccountId,
      orderAccountById,
    })
  }

  traceTradovateMergedAcquisitionStage({
    targetAccountId: params.targetAccountId,
    accountFills,
    fillsFromItemsRepair,
    repairCandidates,
  })

  const window = fillTimestampWindow(accountFills)
  const repairRecovered = repairCandidates.filter((id) =>
    accountFills.some((f) => tradovateFillStableId(f) === id)
  )

  const historicalCompleteness = assessTradovateHistoricalCompleteness({
    ledger: ledgerSnapshot,
    accountFills,
    incrementalWatermark: params.incrementalWatermark ?? null,
    repairAttempted,
    repairFillIdsRequested: repairCandidates,
    repairFillIdsRecovered: repairRecovered,
  })
  logTradovateHistoricalCompleteness(historicalCompleteness)

  const stats: TradovateFillAcquisitionStats = {
    accountId: params.targetAccountId,
    orderDepsCount: ordersFromDeps.length,
    orderIdsCount: orderIdsFromDeps.length,
    fillLdepsCount: fillsFromLdeps.length,
    fillListCount: fillsFromList.length,
    mergedUniqueFillCount: accountFills.length,
    ...window,
    fillLdepsBatchErrors,
    orderDepsFailed,
    fillListFailed,
    fillItemsRepairCount: fillsFromItemsRepair.length,
    fillItemsRepairRequested: repairCandidates.length,
  }

  if (
    accountFills.length === 0 &&
    !orderDepsFailed &&
    orderIdsFromDeps.length > 0 &&
    fillsFromLdeps.length === 0 &&
    fillLdepsBatchErrors > 0
  ) {
    acquisitionErrors.push("fill_ldeps:all_batches_failed_with_orders_present")
  }

  return {
    accountFills,
    orderAccountById,
    stats,
    acquisitionErrors,
    historicalCompleteness,
    supplementalFillList: fillsFromList,
    ordersFromDeps,
    ordersFromList,
    fillsFromItemsRepair,
  }
}
