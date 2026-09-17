import type { SupabaseClient } from "@supabase/supabase-js"
import {
  releaseBrokerSyncLock,
  tryAcquireBrokerSyncLock,
} from "@/lib/integrations/brokerIntegrationSync"
import { TradovateApiError } from "@/lib/integrations/tradovate/tradovateApiClient"
import {
  parseTradovateFillRow,
  tradovateFillStableId,
  tradovateSide,
} from "@/lib/integrations/tradovate/tradovateFillModels"
import {
  fetchTradovateFillFeesForFillIds,
  fetchTradovateFillList,
  fetchTradovateOrderList,
  resolveTradovateContracts,
} from "@/lib/integrations/tradovate/tradovateMarketDataClient"
import { upsertReconstructedBrokerTrades } from "@/lib/integrations/tradovate/persistBrokerTrades"
import {
  BROKER_EXECUTION_RECONSTRUCTION_SELECT,
  listBrokerExecutionsForExternalAccount,
  refreshBrokerExecutionRowAfterDuplicateInsert,
} from "@/lib/integrations/brokerExecutionIdentity"
import {
  reconstructAllCompletedTrades,
  type ReconstructionFill,
} from "@/lib/integrations/tradovate/tradeReconstruction"
import { logTradovateSync } from "@/lib/integrations/tradovate/tradovateSyncLogger"
import type {
  TradovateSyncFailureCategory,
  TradovateSyncFailureStage,
} from "@/lib/integrations/tradovate/tradovateSyncLogger"

export type TradovateSyncTrigger = "manual" | "auto" | "reconnect" | "startup"

export type TradovateSyncSummary = {
  ok: boolean
  status: string
  trigger: TradovateSyncTrigger
  fetched: number
  newExecutions: number
  duplicateExecutions: number
  tradesCreated: number
  tradesUpdated: number
  newTradeIds: string[]
  updatedTradeIds: string[]
  openPositions: number
  durationMs?: number
  error?: string
  /** Machine code for clients/logs (iOS already decodes optionally). */
  errorCode?: string
  failureCategory?: TradovateSyncFailureCategory
  failureStage?: TradovateSyncFailureStage
}

type MappingRow = {
  id: string
  user_id: string
  connection_id: string
  external_account_id: string
  tradetraxs_account_id: string | null
  sync_enabled: boolean
  status: string
}

async function loadMappingForSync(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  brokerIntegrationAccountId: string,
  options: { autoOnly?: boolean }
): Promise<
  | (MappingRow & {
      account: {
        id: string
        name: string
        account_size: string | null
        mode: string | null
        category: string | null
      }
    })
  | null
> {
  const { data: mapping, error } = await supabase
    .from("broker_integration_accounts")
    .select(
      "id, user_id, connection_id, external_account_id, tradetraxs_account_id, sync_enabled, status"
    )
    .eq("id", brokerIntegrationAccountId)
    .eq("user_id", userId)
    .eq("connection_id", connectionId)
    .eq("provider", "tradovate")
    .maybeSingle()

  if (error || !mapping?.tradetraxs_account_id) return null
  if (!mapping.sync_enabled || mapping.status === "inactive") return null

  if (options.autoOnly) {
    const { data: syncRow } = await supabase
      .from("broker_integration_account_sync")
      .select("auto_sync_enabled")
      .eq("broker_integration_account_id", brokerIntegrationAccountId)
      .maybeSingle()
    if (syncRow && syncRow.auto_sync_enabled === false) return null
  }

  const { data: account } = await supabase
    .from("accounts")
    .select("id, name, account_size, mode, category, user_id")
    .eq("id", mapping.tradetraxs_account_id)
    .eq("user_id", userId)
    .maybeSingle()

  if (!account) return null

  return {
    ...(mapping as MappingRow),
    account: {
      id: String(account.id),
      name: String(account.name ?? ""),
      account_size: account.account_size != null ? String(account.account_size) : null,
      mode: account.mode != null ? String(account.mode) : null,
      category: account.category != null ? String(account.category) : null,
    },
  }
}

function emptySummary(
  trigger: TradovateSyncTrigger,
  patch: Partial<TradovateSyncSummary>
): TradovateSyncSummary {
  return {
    ok: false,
    status: "error",
    trigger,
    fetched: 0,
    newExecutions: 0,
    duplicateExecutions: 0,
    tradesCreated: 0,
    tradesUpdated: 0,
    newTradeIds: [],
    updatedTradeIds: [],
    openPositions: 0,
    ...patch,
  }
}

function failureCategoryForProviderUnavailable(
  stage: TradovateSyncFailureStage
): TradovateSyncFailureCategory {
  switch (stage) {
    case "fill_list":
      return "fill_retrieval_failure"
    case "order_list":
      return "order_retrieval_failure"
    default:
      return "provider_api_failure"
  }
}

/**
 * Canonical Tradovate broker account reconciliation (Phase 4 engine).
 * Manual Sync and automatic worker both call this function.
 */
export async function syncTradovateBrokerAccount(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    brokerIntegrationAccountId: string
    trigger: TradovateSyncTrigger
  }
): Promise<TradovateSyncSummary> {
  const started = Date.now()
  const { userId, connectionId, brokerIntegrationAccountId, trigger } = params
  const autoOnly = trigger !== "manual"

  logTradovateSync("sync_started", {
    userId,
    connectionId,
    mappingId: brokerIntegrationAccountId,
    provider: "tradovate",
    trigger,
  })

  const mapping = await loadMappingForSync(
    supabase,
    userId,
    connectionId,
    brokerIntegrationAccountId,
    { autoOnly }
  )
  if (!mapping) {
    logTradovateSync("sync_error", {
      userId,
      connectionId,
      mappingId: brokerIntegrationAccountId,
      trigger,
      failureCategory: "mapping_unavailable",
      failureStage: "mapping",
      errorCode: "mapping_unavailable",
    })
    return emptySummary(trigger, {
      error: autoOnly
        ? "Automatic sync is disabled or account is not linked."
        : "Linked account not available.",
      errorCode: "mapping_unavailable",
      failureCategory: "mapping_unavailable",
      failureStage: "mapping",
    })
  }

  const locked = await tryAcquireBrokerSyncLock(supabase, {
    mappingId: brokerIntegrationAccountId,
    userId,
    connectionId,
  })
  if (!locked) {
    logTradovateSync("sync_coalesced_lock", {
      connectionId,
      mappingId: brokerIntegrationAccountId,
      trigger,
      coalesced: true,
      failureCategory: "sync_lock",
      failureStage: "lock",
      errorCode: "sync_in_progress",
    })
    return emptySummary(trigger, {
      status: "syncing",
      error: "Sync already in progress.",
      errorCode: "sync_in_progress",
      failureCategory: "sync_lock",
      failureStage: "lock",
    })
  }

  const targetAccountId = String(mapping.external_account_id)
  let failureStage: TradovateSyncFailureStage = "unknown"

  try {
    let fillsRaw: Awaited<ReturnType<typeof fetchTradovateFillList>>
    let ordersRaw: Awaited<ReturnType<typeof fetchTradovateOrderList>>
    try {
      failureStage = "fill_list"
      fillsRaw = await fetchTradovateFillList(supabase, userId, connectionId)
    } catch (err) {
      const code =
        err instanceof TradovateApiError ? err.code : "fill_retrieval_failed"
      logTradovateSync("sync_error", {
        userId,
        connectionId,
        mappingId: brokerIntegrationAccountId,
        trigger,
        failureCategory:
          err instanceof TradovateApiError && err.code === "reconnect_required"
            ? "token_refresh_failure"
            : "fill_retrieval_failure",
        failureStage: "fill_list",
        errorCode: code,
        providerHttpStatus:
          err instanceof TradovateApiError ? err.httpStatus : undefined,
      })
      throw err
    }
    try {
      failureStage = "order_list"
      ordersRaw = await fetchTradovateOrderList(supabase, userId, connectionId)
    } catch (err) {
      const code =
        err instanceof TradovateApiError ? err.code : "order_retrieval_failed"
      logTradovateSync("sync_error", {
        userId,
        connectionId,
        mappingId: brokerIntegrationAccountId,
        trigger,
        failureCategory:
          err instanceof TradovateApiError && err.code === "reconnect_required"
            ? "token_refresh_failure"
            : "order_retrieval_failure",
        failureStage: "order_list",
        errorCode: code,
        providerHttpStatus:
          err instanceof TradovateApiError ? err.httpStatus : undefined,
      })
      throw err
    }

    const orderAccountById = new Map<string, string>()
    for (const order of ordersRaw) {
      if (order.id == null || order.accountId == null) continue
      orderAccountById.set(String(order.id), String(order.accountId))
    }

    const accountFills = fillsRaw
      .map(parseTradovateFillRow)
      .filter((row): row is NonNullable<typeof row> => Boolean(row))
      .filter((fill) => {
        const accountId = orderAccountById.get(String(fill.orderId))
        return accountId === targetAccountId
      })

    let newExecutions = 0
    let duplicateExecutions = 0
    let maxFillId: number | null = null
    let maxExecutedAt: string | null = null

    const contractIdsForResolve = new Set<string>()

    failureStage = "persist_executions"
    for (const fill of accountFills) {
      const fillId = tradovateFillStableId(fill)
      const fillIdNum = Number(fillId)
      if (Number.isFinite(fillIdNum)) {
        maxFillId =
          maxFillId == null ? fillIdNum : Math.max(maxFillId, fillIdNum)
      }
      if (fill.timestamp) {
        const ts = String(fill.timestamp)
        if (!maxExecutedAt || ts > maxExecutedAt) maxExecutedAt = ts
      }

      contractIdsForResolve.add(String(fill.contractId))

      const { error: insertError } = await supabase
        .from("broker_integration_executions")
        .insert({
          user_id: userId,
          connection_id: connectionId,
          broker_integration_account_id: brokerIntegrationAccountId,
          provider: "tradovate",
          external_fill_id: String(fillId),
          external_order_id:
            fill.orderId != null ? String(fill.orderId) : null,
          external_contract_id: String(fill.contractId),
          side: tradovateSide(fill),
          quantity: Number(fill.qty),
          price: Number(fill.price),
          executed_at: fill.timestamp,
          provider_metadata: {
            tradeDate: fill.tradeDate ?? null,
            active: fill.active ?? null,
            finallyPaired: fill.finallyPaired ?? null,
          },
          updated_at: new Date().toISOString(),
        })

      if (insertError) {
        if (insertError.code === "23505") {
          duplicateExecutions += 1
          await refreshBrokerExecutionRowAfterDuplicateInsert(supabase, {
            userId,
            provider: "tradovate",
            externalFillId: String(fillId),
            connectionId,
            brokerIntegrationAccountId,
          })
        } else {
          logTradovateSync("sync_error", {
            userId,
            connectionId,
            mappingId: brokerIntegrationAccountId,
            trigger,
            failureCategory: "execution_persistence_failure",
            failureStage: "persist_executions",
            errorCode: insertError.code ?? "execution_persist_failed",
            detail: "broker_integration_executions_insert",
          })
          throw new Error("execution_persist_failed")
        }
      } else {
        newExecutions += 1
      }
    }

    failureStage = "resolve_contracts"
    const contracts = await resolveTradovateContracts(
      supabase,
      userId,
      connectionId,
      [...contractIdsForResolve]
    )

    for (const [contractId, meta] of contracts) {
      await supabase
        .from("broker_integration_executions")
        .update({
          contract_name: meta.contractName,
          symbol_root: meta.symbolRoot,
          updated_at: new Date().toISOString(),
        })
        .eq("broker_integration_account_id", brokerIntegrationAccountId)
        .eq("external_contract_id", String(contractId))
    }

    const storedExecutions = await listBrokerExecutionsForExternalAccount(
      supabase,
      {
        userId,
        provider: "tradovate",
        externalAccountId: targetAccountId,
        fallbackMappingId: brokerIntegrationAccountId,
        select: BROKER_EXECUTION_RECONSTRUCTION_SELECT,
      }
    )

    failureStage = "reconstruct"
    const reconstructionFills: ReconstructionFill[] = storedExecutions.map((row) => ({
      fillId: String(row.external_fill_id),
      contractId: String(row.external_contract_id),
      timestamp: row.executed_at,
      action: row.side === "Sell" ? "Sell" : "Buy",
      qty: Number(row.quantity),
      price: Number(row.price),
    }))

    const { completed, openByContract } = reconstructAllCompletedTrades(
      reconstructionFills,
      targetAccountId
    )

    const feeFillIds = [...new Set(completed.flatMap((t) => t.fillIds))]
    failureStage = "fetch_fees"
    let feesByFillId = new Map<
      string,
      { clearingFee: number; exchangeFee: number; nfaFee: number; commission: number }
    >()
    try {
      feesByFillId = await fetchTradovateFillFeesForFillIds(
        supabase,
        userId,
        connectionId,
        feeFillIds
      )
    } catch (feeErr) {
      // Fills/orders already succeeded with the same connection. Fee enrichment
      // must not convert a mid-sync auth glitch into reconnect_required and
      // abort the import — persist trades with zeroed fees instead.
      if (!(feeErr instanceof TradovateApiError)) throw feeErr
      feesByFillId = new Map()
    }

    failureStage = "persist_trades"
    const { tradesCreated, tradesUpdated, newTradeIds, updatedTradeIds } =
      await upsertReconstructedBrokerTrades(
      supabase,
      {
        userId,
        connectionId,
        mappingId: brokerIntegrationAccountId,
        externalBrokerAccountId: targetAccountId,
        account: mapping.account,
        completed,
        contracts,
        feesByFillId,
      }
    ).catch((err) => {
      logTradovateSync("sync_error", {
        userId,
        connectionId,
        mappingId: brokerIntegrationAccountId,
        trigger,
        failureCategory: "supabase_write_failure",
        failureStage: "persist_trades",
        errorCode: "trade_upsert_failed",
        detail: err instanceof Error ? err.message.slice(0, 120) : "unknown",
      })
      throw err
    })

    const successAt = new Date().toISOString()
    const durationMs = Date.now() - started
    await releaseBrokerSyncLock(supabase, brokerIntegrationAccountId, {
      lastSyncStatus: "success",
      lastSyncSuccessAt: successAt,
      lastSyncErrorCode: null,
      lastSyncErrorMessage: null,
      maxExternalFillId: maxFillId != null ? String(maxFillId) : null,
      maxExecutedAt: maxExecutedAt,
      lastAutoSyncAt: trigger === "manual" ? undefined : successAt,
    })

    logTradovateSync("fills_fetched", {
      connectionId,
      mappingId: brokerIntegrationAccountId,
      trigger,
      fetched: accountFills.length,
      newExecutions,
      provider: "tradovate",
    })

    logTradovateSync("sync_success", {
      userId,
      connectionId,
      mappingId: brokerIntegrationAccountId,
      trigger,
      durationMs,
      fetched: accountFills.length,
      newExecutions,
      tradesCreated,
      tradesUpdated,
    })

    return {
      ok: true,
      status: "success",
      trigger,
      fetched: accountFills.length,
      newExecutions,
      duplicateExecutions,
      tradesCreated,
      tradesUpdated,
      newTradeIds,
      updatedTradeIds,
      openPositions: openByContract.size,
      durationMs,
    }
  } catch (err) {
    let code = "sync_failed"
    let message = "Could not sync trades."
    let failureCategory: TradovateSyncFailureCategory = "sync_failed"
    let providerHttpStatus: number | undefined
    if (err instanceof TradovateApiError) {
      code = err.code
      providerHttpStatus = err.httpStatus
      if (err.code === "reconnect_required") {
        message = "Tradovate authorization expired. Reconnect this connection."
        failureCategory = "token_refresh_failure"
      } else if (err.code === "provider_unavailable") {
        message = "Tradovate is temporarily unavailable."
        failureCategory = failureCategoryForProviderUnavailable(failureStage)
      } else if (err.code === "unauthorized" || err.code === "not_connected") {
        failureCategory = "token_refresh_failure"
        message =
          err.code === "not_connected"
            ? "Tradovate connection is not available. Reconnect this connection."
            : "Tradovate authorization expired. Reconnect this connection."
      } else {
        failureCategory = "provider_api_failure"
      }
    } else if (err instanceof Error) {
      message = err.message
      if (message === "execution_persist_failed") {
        failureCategory = "execution_persistence_failure"
        code = "execution_persist_failed"
        failureStage = "persist_executions"
      } else if (message === "trade_upsert_failed" || failureStage === "persist_trades") {
        failureCategory = "supabase_write_failure"
        code = code === "sync_failed" ? "trade_upsert_failed" : code
      } else if (
        message.includes("reconstruct") ||
        message.includes("lifecycle")
      ) {
        failureCategory = "reconstruction_failure"
        failureStage = "reconstruct"
      }
    }

    await releaseBrokerSyncLock(supabase, brokerIntegrationAccountId, {
      lastSyncStatus:
        err instanceof TradovateApiError &&
        (err.code === "reconnect_required" || err.code === "unauthorized")
          ? "reconnect_required"
          : "error",
      lastSyncErrorCode: code,
      lastSyncErrorMessage: message,
    })

    logTradovateSync("sync_error", {
      userId,
      connectionId,
      mappingId: brokerIntegrationAccountId,
      trigger,
      durationMs: Date.now() - started,
      errorCode: code,
      failureCategory,
      failureStage,
      providerHttpStatus,
      detail: message.slice(0, 120),
    })

    return emptySummary(trigger, {
      status:
        err instanceof TradovateApiError &&
        (err.code === "reconnect_required" ||
          err.code === "unauthorized" ||
          err.code === "not_connected")
          ? "reconnect_required"
          : "error",
      error: message,
      errorCode: code,
      failureCategory,
      failureStage,
      durationMs: Date.now() - started,
    })
  }
}
