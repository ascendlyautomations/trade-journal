import type { SupabaseClient } from "@supabase/supabase-js"
import { tradovateAuthedJsonRequest } from "./tradovateApiClient.ts"
import {
  fetchTradovateFillList,
  fetchTradovateFillsByOrderIdsLdeps,
  fetchTradovateFillPairList,
  fetchTradovateFillPairsByPositionIdsLdeps,
  fetchTradovateOrdersByAccountDeps,
  fetchTradovateOrdersByIds,
  fetchTradovatePositionsByAccountDeps,
} from "./tradovateMarketDataClient.ts"
import type { TradovateFillRaw } from "./tradovateFillModels.ts"
import type { TradovateFillPairRaw } from "./tradovateFillPairModels.ts"

export const TRADOVATE_MISSING_FILL_TRACE_IDS = [
  "660290950326",
  "660290950296",
  "660290950290",
] as const

export type TradovateFillEntityTraceFillSummary = {
  id: string
  orderId: string | null
  contractId: string | null
  timestamp: string | null
  tradeDate: unknown
  action: string | null
  qty: number | null
  price: number | null
}

export type TradovateFillEntityTraceMatrixRow = {
  fillId: string
  fillItems: boolean
  fillList: boolean
  orderItems: boolean | null
  orderDepsAccount: boolean | null
  fillLdepsOrder: boolean | null
  fillPair: boolean
  accountId: string | null
  contractId: string | null
}

export type TradovateMissingFillEntityTraceResult = {
  accountId: string
  connectionId: string
  userId: string
  mappingId: string
  apiEnvironment: string | null
  providerUserId: string | null
  fillListSampleFillIds: string[]
  orderDepsSampleOrderIds: string[]
  fillItems: TradovateFillEntityTraceFillSummary[]
  fillListTotalCount: number
  fillListFound: Record<string, boolean>
  ordersFromItems: {
    fillId: string
    orderId: string | null
    found: boolean
    accountId: string | null
    contractId: string | null
  }[]
  orderDepsAccountOrderCount: number
  orderDepsPresent: Record<string, boolean>
  fillLdeps: {
    orderIdsQueried: string[]
    fillCount: number
    batchErrors: string[]
    found: Record<string, boolean>
  }
  fillPairs: {
    fillPairListCount: number
    positionDepsCount: number
    fillPairLdepsCount: number
    matches: {
      fillId: string
      pairId: string | null
      positionId: string | null
      buyFillId: string | null
      sellFillId: string | null
    }[]
  }
  matrix: TradovateFillEntityTraceMatrixRow[]
}

function fillIdOf(row: TradovateFillRaw): string {
  return String(row.id)
}

function summarizeFill(row: TradovateFillRaw): TradovateFillEntityTraceFillSummary {
  return {
    id: fillIdOf(row),
    orderId: row.orderId != null ? String(row.orderId) : null,
    contractId: row.contractId != null ? String(row.contractId) : null,
    timestamp: row.timestamp ?? null,
    tradeDate: row.tradeDate ?? null,
    action: row.action != null ? String(row.action) : null,
    qty: row.qty ?? null,
    price: row.price ?? null,
  }
}

async function fetchFillItems(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  ids: string[]
): Promise<TradovateFillRaw[]> {
  if (ids.length === 0) return []
  const path = `/v1/fill/items?ids=${ids.map((id) => encodeURIComponent(id)).join(",")}`
  const rows = await tradovateAuthedJsonRequest<unknown[]>(
    supabase,
    userId,
    connectionId,
    path
  )
  if (!Array.isArray(rows)) return []
  return rows.filter((r) => r && typeof r === "object") as TradovateFillRaw[]
}

function pairsTouchingFill(
  pairs: TradovateFillPairRaw[],
  fillId: string
): TradovateFillPairRaw[] {
  return pairs.filter((p) => {
    const buy = p.buyFillId != null ? String(p.buyFillId) : ""
    const sell = p.sellFillId != null ? String(p.sellFillId) : ""
    return buy === fillId || sell === fillId
  })
}

export async function resolveConnectedTradovateMapping(
  supabase: SupabaseClient,
  externalAccountId: string
): Promise<{
  userId: string
  connectionId: string
  accountId: string
  mappingId: string
}> {
  const { data: mappings, error } = await supabase
    .from("broker_integration_accounts")
    .select("id, user_id, connection_id, external_account_id")
    .eq("provider", "tradovate")
    .eq("external_account_id", externalAccountId)

  if (error || !mappings?.length) {
    throw new Error(`No Tradovate mapping for external_account_id=${externalAccountId}`)
  }

  for (const row of mappings) {
    const { data: conn } = await supabase
      .from("broker_integration_connections")
      .select("status")
      .eq("id", row.connection_id)
      .maybeSingle()
    if (conn?.status === "connected") {
      return {
        userId: String(row.user_id),
        connectionId: String(row.connection_id),
        accountId: String(row.external_account_id),
        mappingId: String(row.id),
      }
    }
  }

  throw new Error(
    `No connected Tradovate connection for external_account_id=${externalAccountId}`
  )
}

export async function runTradovateMissingFillEntityTrace(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    accountId: string
    mappingId: string
    apiEnvironment?: string | null
    providerUserId?: string | null
    fillIds?: readonly string[]
  }
): Promise<TradovateMissingFillEntityTraceResult> {
  const targetIds = [...(params.fillIds ?? TRADOVATE_MISSING_FILL_TRACE_IDS)]

  const fillItems = await fetchFillItems(
    supabase,
    params.userId,
    params.connectionId,
    targetIds
  )
  const fillItemsById = new Map(fillItems.map((f) => [fillIdOf(f), f]))

  const fillList = await fetchTradovateFillList(
    supabase,
    params.userId,
    params.connectionId
  )
  const fillListIds = new Set(fillList.map((f) => fillIdOf(f)))
  const fillListFound: Record<string, boolean> = {}
  for (const id of targetIds) {
    fillListFound[id] = fillListIds.has(id)
  }

  const orderIdsFromItems = [
    ...new Set(
      fillItems
        .map((f) => (f.orderId != null ? String(f.orderId) : ""))
        .filter(Boolean)
    ),
  ]

  const ordersFromItems =
    orderIdsFromItems.length > 0
      ? await fetchTradovateOrdersByIds(
          supabase,
          params.userId,
          params.connectionId,
          orderIdsFromItems
        )
      : []
  const orderById = new Map(
    ordersFromItems.map((o) => [String(o.id), o] as const)
  )

  const ordersFromDeps = await fetchTradovateOrdersByAccountDeps(
    supabase,
    params.userId,
    params.connectionId,
    params.accountId
  )
  const orderIdsFromDeps = new Set(
    ordersFromDeps.filter((o) => o.id != null).map((o) => String(o.id))
  )

  const ldepsForTraceOrders =
    orderIdsFromItems.length > 0
      ? await fetchTradovateFillsByOrderIdsLdeps(
          supabase,
          params.userId,
          params.connectionId,
          orderIdsFromItems
        )
      : { fills: [], batchErrors: [] as string[] }

  const ldepsFillIds = new Set(
    ldepsForTraceOrders.fills.map((f) => fillIdOf(f))
  )
  const ldepsFound: Record<string, boolean> = {}
  for (const id of targetIds) {
    ldepsFound[id] = ldepsFillIds.has(id)
  }

  const fillPairList = await fetchTradovateFillPairList(
    supabase,
    params.userId,
    params.connectionId
  )
  const positions = await fetchTradovatePositionsByAccountDeps(
    supabase,
    params.userId,
    params.connectionId,
    params.accountId
  )
  const positionIds = positions
    .map((p) => (p.id != null ? String(p.id) : ""))
    .filter(Boolean)
  const { pairs: fillPairsFromPositions } =
    await fetchTradovateFillPairsByPositionIdsLdeps(
      supabase,
      params.userId,
      params.connectionId,
      positionIds
    )
  const allPairsRaw: TradovateFillPairRaw[] = [
    ...fillPairList,
    ...fillPairsFromPositions,
  ]

  const orderDepsPresent: Record<string, boolean> = {}
  for (const fillId of targetIds) {
    const fill = fillItemsById.get(fillId)
    const orderId = fill?.orderId != null ? String(fill.orderId) : null
    orderDepsPresent[fillId] = orderId ? orderIdsFromDeps.has(orderId) : false
  }

  const ordersFromItemsReport = targetIds.map((fillId) => {
    const fill = fillItemsById.get(fillId)
    const orderId = fill?.orderId != null ? String(fill.orderId) : null
    const order = orderId ? orderById.get(orderId) : undefined
    return {
      fillId,
      orderId,
      found: Boolean(order && orderId),
      accountId: order?.accountId != null ? String(order.accountId) : null,
      contractId: order?.contractId != null ? String(order.contractId) : null,
    }
  })

  const fillPairMatches: TradovateMissingFillEntityTraceResult["fillPairs"]["matches"] =
    []
  for (const fillId of targetIds) {
    for (const p of pairsTouchingFill(allPairsRaw, fillId)) {
      fillPairMatches.push({
        fillId,
        pairId: p.id != null ? String(p.id) : null,
        positionId: p.positionId != null ? String(p.positionId) : null,
        buyFillId: p.buyFillId != null ? String(p.buyFillId) : null,
        sellFillId: p.sellFillId != null ? String(p.sellFillId) : null,
      })
    }
  }

  const matrix: TradovateFillEntityTraceMatrixRow[] = targetIds.map((fillId) => {
    const fill = fillItemsById.get(fillId)
    const orderId = fill?.orderId != null ? String(fill.orderId) : null
    const order = orderId ? orderById.get(orderId) : undefined
    return {
      fillId,
      fillItems: fillItemsById.has(fillId),
      fillList: fillListIds.has(fillId),
      orderItems: orderId ? Boolean(order) : null,
      orderDepsAccount: orderId ? orderIdsFromDeps.has(orderId) : null,
      fillLdepsOrder: orderId ? ldepsFillIds.has(fillId) : null,
      fillPair: pairsTouchingFill(allPairsRaw, fillId).length > 0,
      accountId:
        order?.accountId != null
          ? String(order.accountId)
          : fill?.orderId
            ? null
            : null,
      contractId:
        fill?.contractId != null
          ? String(fill.contractId)
          : order?.contractId != null
            ? String(order.contractId)
            : null,
    }
  })

  return {
    accountId: params.accountId,
    connectionId: params.connectionId,
    userId: params.userId,
    mappingId: params.mappingId,
    apiEnvironment: params.apiEnvironment ?? null,
    providerUserId: params.providerUserId ?? null,
    fillListSampleFillIds: fillList.slice(0, 20).map((f) => fillIdOf(f)),
    orderDepsSampleOrderIds: ordersFromDeps
      .slice(0, 20)
      .map((o) => (o.id != null ? String(o.id) : ""))
      .filter(Boolean),
    fillItems: fillItems.map(summarizeFill),
    fillListTotalCount: fillList.length,
    fillListFound,
    ordersFromItems: ordersFromItemsReport,
    orderDepsAccountOrderCount: ordersFromDeps.length,
    orderDepsPresent,
    fillLdeps: {
      orderIdsQueried: orderIdsFromItems,
      fillCount: ldepsForTraceOrders.fills.length,
      batchErrors: ldepsForTraceOrders.batchErrors,
      found: ldepsFound,
    },
    fillPairs: {
      fillPairListCount: fillPairList.length,
      positionDepsCount: positions.length,
      fillPairLdepsCount: fillPairsFromPositions.length,
      matches: fillPairMatches,
    },
    matrix,
  }
}

export function formatTradovateMissingFillEntityTraceMatrix(
  result: TradovateMissingFillEntityTraceResult
): string {
  const lines = [
    "FILL_ID | fill/items | fill/list | order/items | order/deps(account) | fill/ldeps(order) | fillPair | accountId | contractId",
  ]
  for (const row of result.matrix) {
    lines.push(
      [
        row.fillId,
        row.fillItems ? "YES" : "NO",
        row.fillList ? "YES" : "NO",
        row.orderItems == null ? "—" : row.orderItems ? "YES" : "NO",
        row.orderDepsAccount == null ? "—" : row.orderDepsAccount ? "YES" : "NO",
        row.fillLdepsOrder == null ? "—" : row.fillLdepsOrder ? "YES" : "NO",
        row.fillPair ? "YES" : "NO",
        row.accountId ?? "—",
        row.contractId ?? "—",
      ].join(" | ")
    )
  }
  return lines.join("\n")
}
