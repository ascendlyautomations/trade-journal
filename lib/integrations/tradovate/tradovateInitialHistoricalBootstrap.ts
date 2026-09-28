import type { SupabaseClient } from "@supabase/supabase-js"
import {
  tradovateAuthedFetch,
  TradovateApiError,
} from "./tradovateApiClient.ts"
import type { TradovateFillRaw, TradovateOrderRaw } from "./tradovateFillModels.ts"
import { tradovateFillStableId } from "./tradovateFillModels.ts"
import {
  collectFillIdsFromCashBalanceLogs,
  filterCashBalanceLogsWithinLookback,
  type TradovateCashBalanceLogRaw,
} from "./tradovateCashBalanceLogModels.ts"
import {
  fetchTradovateFillsByIds,
  fetchTradovateFillsByOrderIdsLdeps,
} from "./tradovateMarketDataClient.ts"
import { dedupeTradovateFillsById } from "./tradovateFillAcquisitionCore.ts"

/** Product default when Tradovate does not accept explicit date ranges on REST deps. */
export const TRADOVATE_INITIAL_BOOTSTRAP_LOOKBACK_DAYS = 365

export type TradovateBootstrapHttpDiagnostic = {
  httpStatus: number
  category: string
}

export type TradovateInitialHistoricalBootstrapResult = {
  attempted: boolean
  cashBalanceLogCount: number
  cashBalanceLogFillIds: string[]
  executionReportOrderIds: string[]
  orderLdepsCount: number
  discoveredFillIds: string[]
  fills: TradovateFillRaw[]
  errors: string[]
  executionReportListRawCount: number
  executionReportAccountMatchedCount: number
  executionReportAccountOrderIdCount: number
  orderLdepsRawCount: number
  orderLdepsAccountMatchedCount: number
  cashBalanceLogDepsRawCount: number
  cashBalanceLogFillIdCount: number
  httpDiagnostics: {
    cashBalanceLogDeps: TradovateBootstrapHttpDiagnostic
    executionReportList: TradovateBootstrapHttpDiagnostic
    orderLdeps: TradovateBootstrapHttpDiagnostic
  }
}

function bootstrapLookbackStartIso(now = new Date()): string {
  const start = new Date(now)
  start.setUTCDate(start.getUTCDate() - TRADOVATE_INITIAL_BOOTSTRAP_LOOKBACK_DAYS)
  return start.toISOString()
}

function parseObjectArray(body: unknown): Record<string, unknown>[] {
  if (!Array.isArray(body)) return []
  return body.filter((row) => row && typeof row === "object") as Record<string, unknown>[]
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
  const target = String(params.targetAccountId).trim()
  const masterid = encodeURIComponent(target)

  const emptyHttp = { httpStatus: 0, category: "skipped" as const }

  let cashBalanceLogDepsRawCount = 0
  let cashBalanceLogFillIdCount = 0
  let cashBalanceLogCount = 0
  let cashBalanceLogs: TradovateCashBalanceLogRaw[] = []
  let cashBalanceHttp: TradovateBootstrapHttpDiagnostic = emptyHttp

  const cashBalanceFetch = await tradovateAuthedFetch(
    supabase,
    params.userId,
    params.connectionId,
    `/v1/cashBalanceLog/deps?masterid=${masterid}`
  )
  cashBalanceHttp = {
    httpStatus: cashBalanceFetch.status,
    category: cashBalanceFetch.category,
  }
  if (cashBalanceFetch.ok) {
    cashBalanceLogs = parseObjectArray(cashBalanceFetch.json) as TradovateCashBalanceLogRaw[]
    cashBalanceLogDepsRawCount = cashBalanceLogs.length
    cashBalanceLogCount = cashBalanceLogs.length
    cashBalanceLogs = filterCashBalanceLogsWithinLookback(
      cashBalanceLogs,
      lookbackStart
    )
    cashBalanceLogFillIdCount = collectFillIdsFromCashBalanceLogs(cashBalanceLogs).length
  } else {
    errors.push(
      `cash_balance_log_deps:http_${cashBalanceFetch.status}:${cashBalanceFetch.category}`
    )
  }

  const cashBalanceLogFillIds = collectFillIdsFromCashBalanceLogs(cashBalanceLogs)

  let executionReportListRawCount = 0
  let executionReportAccountMatchedCount = 0
  let executionReportOrderIds: string[] = []
  let executionReportHttp: TradovateBootstrapHttpDiagnostic = emptyHttp

  const executionReportFetch = await tradovateAuthedFetch(
    supabase,
    params.userId,
    params.connectionId,
    "/v1/executionReport/list"
  )
  executionReportHttp = {
    httpStatus: executionReportFetch.status,
    category: executionReportFetch.category,
  }
  if (executionReportFetch.ok) {
    const reports = parseObjectArray(executionReportFetch.json) as Array<{
      accountId?: number | string
      orderId?: number | string
    }>
    executionReportListRawCount = reports.length
    executionReportAccountMatchedCount = reports.filter(
      (r) => r.accountId != null && String(r.accountId).trim() === target
    ).length
    executionReportOrderIds = collectOrderIdsFromExecutionReports({
      reports,
      targetAccountId: params.targetAccountId,
    })
  } else {
    errors.push(
      `execution_report_list:http_${executionReportFetch.status}:${executionReportFetch.category}`
    )
  }

  let orderLdepsRawCount = 0
  let orderLdepsAccountMatchedCount = 0
  let orderLdepsCount = 0
  let orderIdsFromLdeps: string[] = []
  let orderLdepsHttp: TradovateBootstrapHttpDiagnostic = emptyHttp

  const orderLdepsFetch = await tradovateAuthedFetch(
    supabase,
    params.userId,
    params.connectionId,
    `/v1/order/ldeps?masterids=${masterid}`
  )
  orderLdepsHttp = {
    httpStatus: orderLdepsFetch.status,
    category: orderLdepsFetch.category,
  }
  if (orderLdepsFetch.ok) {
    const orders = parseObjectArray(orderLdepsFetch.json) as TradovateOrderRaw[]
    orderLdepsRawCount = orders.length
    orderLdepsAccountMatchedCount = orders.filter(
      (o) => o.accountId != null && String(o.accountId).trim() === target
    ).length
    orderLdepsCount = orders.length
    orderIdsFromLdeps = [
      ...new Set(
        orders.filter((o) => o.id != null).map((o) => String(o.id))
      ),
    ]
  } else {
    errors.push(
      `order_ldeps:http_${orderLdepsFetch.status}:${orderLdepsFetch.category}`
    )
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
    executionReportListRawCount,
    executionReportAccountMatchedCount,
    executionReportAccountOrderIdCount: executionReportOrderIds.length,
    orderLdepsRawCount,
    orderLdepsAccountMatchedCount,
    cashBalanceLogDepsRawCount,
    cashBalanceLogFillIdCount,
    httpDiagnostics: {
      cashBalanceLogDeps: cashBalanceHttp,
      executionReportList: executionReportHttp,
      orderLdeps: orderLdepsHttp,
    },
  }
}
