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
    return emptySummary(trigger, {
      error: autoOnly
        ? "Automatic sync is disabled or account is not linked."
        : "Linked account not available.",
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
    })
    return emptySummary(trigger, {
      status: "syncing",
      error: "Sync already in progress.",
    })
  }

  const targetAccountId = String(mapping.external_account_id)

  try {
    const [fillsRaw, ordersRaw] = await Promise.all([
      fetchTradovateFillList(supabase, userId, connectionId),
      fetchTradovateOrderList(supabase, userId, connectionId),
    ])

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
        } else throw new Error("execution_persist_failed")
      } else {
        newExecutions += 1
      }
    }

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
    const feesByFillId = await fetchTradovateFillFeesForFillIds(
      supabase,
      userId,
      connectionId,
      feeFillIds
    )

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
    )

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
    if (err instanceof TradovateApiError) {
      code = err.code
      if (err.code === "reconnect_required") {
        message = "Tradovate authorization expired. Reconnect this connection."
      } else if (err.code === "provider_unavailable") {
        message = "Tradovate is temporarily unavailable."
      }
    } else if (err instanceof Error) {
      message = err.message
    }

    await releaseBrokerSyncLock(supabase, brokerIntegrationAccountId, {
      lastSyncStatus:
        err instanceof TradovateApiError && err.code === "reconnect_required"
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
    })

    return emptySummary(trigger, {
      status:
        err instanceof TradovateApiError && err.code === "reconnect_required"
          ? "reconnect_required"
          : "error",
      error: message,
      durationMs: Date.now() - started,
    })
  }
}
