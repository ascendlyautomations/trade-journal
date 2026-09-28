import type { SupabaseClient } from "@supabase/supabase-js"
import { TradovateApiError } from "./tradovateApiClient.ts"
import type { TradovateFillRaw } from "./tradovateFillModels.ts"
import { tradovateFillStableId } from "./tradovateFillModels.ts"
import {
  collectFillIdsFromCashBalanceLogs,
  filterCashBalanceLogsWithinLookback,
  type TradovateCashBalanceLogRaw,
} from "./tradovateCashBalanceLogModels.ts"
import {
  fetchTradovateCashBalanceLogsByAccountDeps,
  fetchTradovateExecutionReportList,
  fetchTradovateFillsByIds,
  fetchTradovateFillsByOrderIdsLdeps,
  fetchTradovateOrdersByAccountIdsLdeps,
} from "./tradovateMarketDataClient.ts"
import { dedupeTradovateFillsById } from "./tradovateFillAcquisitionCore.ts"

/** Product default when Tradovate does not accept explicit date ranges on REST deps. */
export const TRADOVATE_INITIAL_BOOTSTRAP_LOOKBACK_DAYS = 365

export type TradovateInitialHistoricalBootstrapResult = {
  attempted: boolean
  cashBalanceLogCount: number
  cashBalanceLogFillIds: string[]
  executionReportOrderIds: string[]
  orderLdepsCount: number
  discoveredFillIds: string[]
  fills: TradovateFillRaw[]
  errors: string[]
}

function bootstrapLookbackStartIso(now = new Date()): string {
  const start = new Date(now)
  start.setUTCDate(start.getUTCDate() - TRADOVATE_INITIAL_BOOTSTRAP_LOOKBACK_DAYS)
  return start.toISOString()
}

export function collectOrderIdsFromExecutionReports(params: {
  reports: Array<{ accountId?: number | string; orderId?: number | string }>
  targetAccountId: string
}): string[] {
  const target = String(params.targetAccountId).trim()
  const out = new Set<string>()
  for (const row of params.reports) {
    if (row.accountId == null || row.orderId == null) continue
    if (String(row.accountId).trim() !== target) continue
    out.add(String(row.orderId))
  }
  return [...out]
}

/**
 * Initial ledger bootstrap when list/deps return no recent orders/fills.
 *
 * Supported Tradovate REST (OAuth bearer):
 * - GET cashBalanceLog/deps?masterid={accountId} — accounting logs with fillId pointers (archival).
 * - GET executionReport/list — user-visible execution reports; filter by accountId → order ids → fill/ldeps.
 * - GET order/ldeps?masterids={accountId} — supplemental order discovery for account entity.
 * - GET fill/items?ids= — hydrate fills discovered via logs or ldeps.
 */
export async function runTradovateInitialHistoricalBootstrap(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    targetAccountId: string
    alreadyMergedFillIds: Set<string>
  }
): Promise<TradovateInitialHistoricalBootstrapResult> {
  const errors: string[] = []
  const lookbackStart = bootstrapLookbackStartIso()
  let cashBalanceLogCount = 0
  let cashBalanceLogs: TradovateCashBalanceLogRaw[] = []

  try {
    cashBalanceLogs = await fetchTradovateCashBalanceLogsByAccountDeps(
      supabase,
      params.userId,
      params.connectionId,
      params.targetAccountId
    )
    cashBalanceLogCount = cashBalanceLogs.length
    cashBalanceLogs = filterCashBalanceLogsWithinLookback(
      cashBalanceLogs,
      lookbackStart
    )
  } catch (err) {
    const detail =
      err instanceof TradovateApiError
        ? `${err.code}:${err.message}`
        : err instanceof Error
          ? err.message
          : "cash_balance_log_deps_failed"
    errors.push(`cash_balance_log_deps:${detail}`)
  }

  const cashBalanceLogFillIds = collectFillIdsFromCashBalanceLogs(cashBalanceLogs)

  let executionReportOrderIds: string[] = []
  try {
    const reports = await fetchTradovateExecutionReportList(
      supabase,
      params.userId,
      params.connectionId
    )
    executionReportOrderIds = collectOrderIdsFromExecutionReports({
      reports,
      targetAccountId: params.targetAccountId,
    })
  } catch (err) {
    const detail =
      err instanceof TradovateApiError
        ? `${err.code}:${err.message}`
        : err instanceof Error
          ? err.message
          : "execution_report_list_failed"
    errors.push(`execution_report_list:${detail}`)
  }

  let orderLdepsCount = 0
  let orderIdsFromLdeps: string[] = []
  try {
    const orders = await fetchTradovateOrdersByAccountIdsLdeps(
      supabase,
      params.userId,
      params.connectionId,
      [params.targetAccountId]
    )
    orderLdepsCount = orders.length
    orderIdsFromLdeps = [
      ...new Set(
        orders.filter((o) => o.id != null).map((o) => String(o.id))
      ),
    ]
  } catch (err) {
    const detail =
      err instanceof TradovateApiError
        ? `${err.code}:${err.message}`
        : err instanceof Error
          ? err.message
          : "order_ldeps_failed"
    errors.push(`order_ldeps:${detail}`)
  }

  const orderIdsForLdeps = [
    ...new Set([...executionReportOrderIds, ...orderIdsFromLdeps]),
  ]

  let fillsFromOrderLdeps: TradovateFillRaw[] = []
  if (orderIdsForLdeps.length > 0) {
    const ldeps = await fetchTradovateFillsByOrderIdsLdeps(
      supabase,
      params.userId,
      params.connectionId,
      orderIdsForLdeps
    )
    fillsFromOrderLdeps = ldeps.fills
    for (const batchErr of ldeps.batchErrors) {
      errors.push(`bootstrap_fill_ldeps:${batchErr}`)
    }
  }

  const fillIdsFromLdeps = new Set(
    fillsFromOrderLdeps
      .filter((f) => f.id != null)
      .map((f) => tradovateFillStableId(f))
  )

  const fillIdsForItems = [
    ...new Set([
      ...cashBalanceLogFillIds,
      ...[...fillIdsFromLdeps].filter((id) => !params.alreadyMergedFillIds.has(id)),
    ]),
  ].filter((id) => !params.alreadyMergedFillIds.has(id))

  let fillsFromItems: TradovateFillRaw[] = []
  if (fillIdsForItems.length > 0) {
    try {
      fillsFromItems = await fetchTradovateFillsByIds(
        supabase,
        params.userId,
        params.connectionId,
        fillIdsForItems
      )
    } catch (err) {
      const detail =
        err instanceof TradovateApiError
          ? `${err.code}:${err.message}`
          : err instanceof Error
            ? err.message
            : "bootstrap_fill_items_failed"
      errors.push(`bootstrap_fill_items:${detail}`)
    }
  }

  const fills = dedupeTradovateFillsById([
    ...fillsFromOrderLdeps,
    ...fillsFromItems,
  ])

  const discoveredFillIds = [
    ...new Set([
      ...cashBalanceLogFillIds,
      ...fills.map((f) => tradovateFillStableId(f)),
    ]),
  ]

  return {
    attempted: true,
    cashBalanceLogCount,
    cashBalanceLogFillIds,
    executionReportOrderIds,
    orderLdepsCount,
    discoveredFillIds,
    fills,
    errors,
  }
}
