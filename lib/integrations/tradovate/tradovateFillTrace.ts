import type { SupabaseClient } from "@supabase/supabase-js"
import type { TradovateFillRaw, TradovateOrderRaw } from "./tradovateFillModels.ts"
import { parseTradovateFillRow } from "./tradovateFillModels.ts"

/** Authoritative Performance.csv MGC fills missing from production ledger. */
export const TRACED_MGC_FILL_IDS = [
  "660290950326",
  "660290950296",
  "660290950290",
] as const

export const TRADOVATE_SYNC_VERSION_MARKER =
  "missingOrderHydration=v2,fillAcquisition=v3,historicalRepair=v1,metadata=v2,fillPairValidation=v2"

const tracedFillIdSet = new Set<string>(TRACED_MGC_FILL_IDS)

/** Investigation fill trace — off in production unless TRADOVATE_FILL_TRACE=1. */
export function isTradovateFillTraceEnabled(): boolean {
  return process.env.TRADOVATE_FILL_TRACE === "1"
}

function whenFillTraceEnabled(run: () => void): void {
  if (isTradovateFillTraceEnabled()) run()
}

export function isTradovateTracedFillId(fillId: string): boolean {
  return tracedFillIdSet.has(String(fillId).trim())
}

export function logTradovateSyncVersionMarker(): void {
  console.info(`[TradovateSyncVersion] ${TRADOVATE_SYNC_VERSION_MARKER}`)
}

type TraceFields = Record<
  string,
  string | number | boolean | null | undefined
>

export function logTradovateFillTrace(fields: TraceFields): void {
  whenFillTraceEnabled(() => {
    const parts = ["[TradovateFillTrace]"]
    for (const [key, value] of Object.entries(fields)) {
      if (value === undefined) continue
      parts.push(`${key}=${value === null ? "null" : String(value)}`)
    }
    console.info(parts.join(" "))
  })
}

function fillRowById(
  fillsRaw: TradovateFillRaw[],
  fillId: string
): TradovateFillRaw | undefined {
  return fillsRaw.find((row) => String(row.id ?? "").trim() === fillId)
}

function fillListWindow(fillsRaw: TradovateFillRaw[]): {
  rawFillCount: number
  earliestFillTimestamp: string | null
  latestFillTimestamp: string | null
} {
  let earliest: string | null = null
  let latest: string | null = null
  for (const row of fillsRaw) {
    const ts = row.timestamp ? String(row.timestamp) : null
    if (!ts) continue
    if (!earliest || ts < earliest) earliest = ts
    if (!latest || ts > latest) latest = ts
  }
  return {
    rawFillCount: fillsRaw.length,
    earliestFillTimestamp: earliest,
    latestFillTimestamp: latest,
  }
}

export function traceTradovateMergedAcquisitionStage(params: {
  targetAccountId: string
  accountFills: TradovateFillRaw[]
  fillsFromItemsRepair: TradovateFillRaw[]
  repairCandidates: string[]
}): void {
  for (const fillId of TRACED_MGC_FILL_IDS) {
    const inRepairRaw = params.fillsFromItemsRepair.some(
      (f) => String(f.id) === fillId
    )
    const inMerged = params.accountFills.some((f) => String(f.id) === fillId)
    logTradovateFillTrace({
      fillId,
      stage: "merged_acquisition",
      targetAccountId: params.targetAccountId,
      foundInFillItemsRepair: inRepairRaw,
      foundInMergedAcquisitionSet: inMerged,
      repairCandidate: params.repairCandidates.includes(fillId),
      dropReason: inMerged
        ? null
        : inRepairRaw
          ? "repair_fill_failed_account_filter"
          : "absent_from_merged_acquisition",
    })
  }
}

export function traceTradovateFillListStage(params: {
  targetAccountId: string
  mappingId: string
  fillsRaw: TradovateFillRaw[]
}): void {
  if (!isTradovateFillTraceEnabled()) return
  whenFillTraceEnabled(() => {
    const window = fillListWindow(params.fillsRaw)
    logTradovateSyncVersionMarker()
    console.info(
      [
        "[TradovateFillTrace]",
        "stage=fill_list_window",
        `rawFillCount=${window.rawFillCount}`,
        `earliestFillTimestamp=${window.earliestFillTimestamp ?? "null"}`,
        `latestFillTimestamp=${window.latestFillTimestamp ?? "null"}`,
        `targetAccountId=${params.targetAccountId}`,
        `mappingId=${params.mappingId}`,
      ].join(" ")
    )
  })

  for (const fillId of TRACED_MGC_FILL_IDS) {
    const row = fillRowById(params.fillsRaw, fillId)
    logTradovateFillTrace({
      fillId,
      stage: "fill_list",
      targetAccountId: params.targetAccountId,
      foundInFillList: Boolean(row),
      orderId: row?.orderId != null ? String(row.orderId) : null,
      contractId: row?.contractId != null ? String(row.contractId) : null,
      dropReason: row ? null : "absent_from_v1_fill_list",
    })
  }
}

export function traceTradovateOrderAndFilterStage(params: {
  targetAccountId: string
  fillsRaw: TradovateFillRaw[]
  ordersRaw: TradovateOrderRaw[]
  orderAccountById: Map<string, string>
  missingOrderIds: string[]
  hydratedOrders: TradovateOrderRaw[]
  accountFillIds: Set<string>
}): void {
  if (!isTradovateFillTraceEnabled()) return
  const hydratedOrderIds = new Set(
    params.hydratedOrders
      .filter((o) => o.id != null)
      .map((o) => String(o.id))
  )

  for (const fillId of TRACED_MGC_FILL_IDS) {
    const raw = fillRowById(params.fillsRaw, fillId)
    if (!raw) {
      logTradovateFillTrace({
        fillId,
        stage: "account_filter_skipped",
        targetAccountId: params.targetAccountId,
        foundInFillList: false,
        dropReason: "absent_from_v1_fill_list",
      })
      continue
    }

    const parsed = parseTradovateFillRow(raw)
    const orderId = raw.orderId != null ? String(raw.orderId) : null
    const orderFoundInOrderList =
      orderId != null &&
      params.ordersRaw.some((o) => String(o.id) === orderId)
    const missingOrderHydrationRequested =
      orderId != null && params.missingOrderIds.includes(orderId)
    const orderItemsReturned =
      orderId != null && hydratedOrderIds.has(orderId)
    const hydratedOrderAccountId =
      orderId != null ? params.orderAccountById.get(orderId) ?? null : null
    const resolvedAccountId = hydratedOrderAccountId
    const passesAccountFilter = params.accountFillIds.has(fillId)

    let dropReason: string | null = null
    if (!parsed) {
      dropReason = "parse_tradovate_fill_row_failed"
    } else if (!orderId) {
      dropReason = "missing_order_id_on_fill"
    } else if (!resolvedAccountId) {
      dropReason = orderItemsReturned
        ? "order_items_returned_without_account_id"
        : missingOrderHydrationRequested
          ? "order_missing_after_list_and_items_hydration"
          : "order_not_in_order_list_and_not_hydrated"
    } else if (resolvedAccountId !== params.targetAccountId) {
      dropReason = "resolved_account_mismatch"
    } else if (!passesAccountFilter) {
      dropReason = "account_filter_excluded_unexpected"
    }

    logTradovateFillTrace({
      fillId,
      stage: "account_filter",
      orderId,
      contractId: raw.contractId != null ? String(raw.contractId) : null,
      accountId: resolvedAccountId,
      targetAccountId: params.targetAccountId,
      foundInFillList: true,
      orderFoundInOrderList,
      missingOrderHydrationRequested,
      orderItemsReturned,
      hydratedOrderAccountId,
      passesAccountFilter,
      dropReason,
    })
  }
}

export type TracedExecutionPersistOutcome = {
  executionInsertAttempted: boolean
  executionInsertSucceeded: boolean
  executionInsertError: string | null
  executionAlreadyExists: boolean
}

export function traceTradovateExecutionPersist(params: {
  fillId: string
  targetAccountId: string
  outcome: TracedExecutionPersistOutcome
}): void {
  if (!isTradovateTracedFillId(params.fillId)) return
  logTradovateFillTrace({
    fillId: params.fillId,
    stage: "execution_persist",
    targetAccountId: params.targetAccountId,
    ...params.outcome,
    dropReason: params.outcome.executionInsertSucceeded
      ? null
      : params.outcome.executionAlreadyExists
        ? "duplicate_execution_no_op"
        : params.outcome.executionInsertAttempted
          ? "execution_insert_failed"
          : "execution_persist_not_attempted",
  })
}

export async function traceTradovateExecutionLedgerAfterPersist(params: {
  supabase: SupabaseClient
  userId: string
  mappingId: string
  targetAccountId: string
}): Promise<void> {
  if (!isTradovateFillTraceEnabled()) return
  const { data, error } = await params.supabase
    .from("broker_integration_executions")
    .select(
      "external_fill_id, external_order_id, external_contract_id, side, quantity, price, executed_at, lifecycle_key, canonical_trade_id"
    )
    .eq("user_id", params.userId)
    .eq("provider", "tradovate")
    .in("external_fill_id", [...TRACED_MGC_FILL_IDS])

  if (error) {
    for (const fillId of TRACED_MGC_FILL_IDS) {
      logTradovateFillTrace({
        fillId,
        stage: "execution_ledger_query",
        targetAccountId: params.targetAccountId,
        presentInExecutionLedgerAfterPersist: false,
        dropReason: `ledger_query_error:${error.code ?? "unknown"}`,
      })
    }
    return
  }

  const byFillId = new Map(
    (data ?? []).map((row) => [String(row.external_fill_id), row] as const)
  )

  for (const fillId of TRACED_MGC_FILL_IDS) {
    const row = byFillId.get(fillId)
    logTradovateFillTrace({
      fillId,
      stage: "execution_ledger_after_persist",
      targetAccountId: params.targetAccountId,
      presentInExecutionLedgerAfterPersist: Boolean(row),
      orderId: row?.external_order_id ?? null,
      contractId: row?.external_contract_id ?? null,
      lifecycleId: row?.lifecycle_key ?? null,
      finalTradeId: row?.canonical_trade_id ?? null,
      dropReason: row ? null : "not_in_broker_integration_executions",
    })
  }
}

export function traceTradovateReconstructionLoad(params: {
  targetAccountId: string
  ledgerExecutionCount: number
  reconstructionExecutionCount: number
  reconstructionFillIds: Set<string>
}): void {
  if (!isTradovateFillTraceEnabled()) return
  console.info(
    [
      "[TradovateFillTrace]",
      "stage=reconstruction_load_summary",
      `ledgerExecutionCount=${params.ledgerExecutionCount}`,
      `reconstructionExecutionCount=${params.reconstructionExecutionCount}`,
      `targetAccountId=${params.targetAccountId}`,
    ].join(" ")
  )

  for (const fillId of TRACED_MGC_FILL_IDS) {
    logTradovateFillTrace({
      fillId,
      stage: "reconstruction_load",
      targetAccountId: params.targetAccountId,
      includedInReconstruction: params.reconstructionFillIds.has(fillId),
      dropReason: params.reconstructionFillIds.has(fillId)
        ? null
        : "not_in_reconstruction_input",
    })
  }
}

export function traceTradovateReconstructionFillStep(params: {
  fillId: string
  contractId: string
  fillSide: string
  quantity: number
  positionBefore: number
  positionAfter: number
  lifecycleOpened: string | null
  lifecycleClosed: string | null
}): void {
  if (!isTradovateTracedFillId(params.fillId)) return
  logTradovateFillTrace({
    fillId: params.fillId,
    stage: "reconstruction_step",
    contractId: params.contractId,
    fillSide: params.fillSide,
    quantity: params.quantity,
    positionBefore: params.positionBefore,
    positionAfter: params.positionAfter,
    lifecycleOpened: params.lifecycleOpened,
    lifecycleClosed: params.lifecycleClosed,
  })
}

export function traceTradovateReconstructionResult(params: {
  targetAccountId: string
  completed: Array<{ lifecycleKey: string; fillIds: string[] }>
}): void {
  if (!isTradovateFillTraceEnabled()) return
  for (const fillId of TRACED_MGC_FILL_IDS) {
    const lifecycle = params.completed.find((t) => t.fillIds.includes(fillId))
    logTradovateFillTrace({
      fillId,
      stage: "reconstruction_result",
      targetAccountId: params.targetAccountId,
      includedInReconstruction: Boolean(lifecycle),
      lifecycleId: lifecycle?.lifecycleKey ?? null,
      dropReason: lifecycle ? null : "fill_not_in_any_completed_lifecycle",
    })
  }
}

export async function traceTradovateFinalTradeIds(params: {
  supabase: SupabaseClient
  userId: string
  targetAccountId: string
  completed: Array<{ lifecycleKey: string; fillIds: string[] }>
}): Promise<void> {
  if (!isTradovateFillTraceEnabled()) return
  for (const fillId of TRACED_MGC_FILL_IDS) {
    const lifecycle = params.completed.find((t) => t.fillIds.includes(fillId))
    if (!lifecycle) {
      logTradovateFillTrace({
        fillId,
        stage: "final_trade",
        targetAccountId: params.targetAccountId,
        finalTradeId: null,
        lifecycleId: null,
        dropReason: "no_lifecycle_for_fill",
      })
      continue
    }

    const { data: byLifecycle } = await params.supabase
      .from("trades")
      .select("id")
      .eq("user_id", params.userId)
      .eq("broker_lifecycle_id", lifecycle.lifecycleKey)
      .maybeSingle()

    const { data: byExecution } = await params.supabase
      .from("broker_integration_executions")
      .select("canonical_trade_id")
      .eq("user_id", params.userId)
      .eq("provider", "tradovate")
      .eq("external_fill_id", fillId)
      .maybeSingle()

    const finalTradeId =
      byLifecycle?.id != null
        ? String(byLifecycle.id)
        : byExecution?.canonical_trade_id != null
          ? String(byExecution.canonical_trade_id)
          : null

    logTradovateFillTrace({
      fillId,
      stage: "final_trade",
      targetAccountId: params.targetAccountId,
      lifecycleId: lifecycle.lifecycleKey,
      finalTradeId,
      dropReason: finalTradeId ? null : "lifecycle_not_persisted_to_trades",
    })
  }
}
