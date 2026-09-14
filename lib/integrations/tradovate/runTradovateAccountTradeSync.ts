import type { SupabaseClient } from "@supabase/supabase-js"
import {
  loadBrokerAccountSyncViews,
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
  reconstructAllCompletedTrades,
  type ReconstructionFill,
} from "@/lib/integrations/tradovate/tradeReconstruction"

export type TradovateSyncSummary = {
  ok: boolean
  status: string
  fetched: number
  newExecutions: number
  duplicateExecutions: number
  tradesCreated: number
  tradesUpdated: number
  openPositions: number
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

async function loadMapping(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  mappingId: string
): Promise<(MappingRow & { account: { id: string; name: string; account_size: string | null; mode: string | null; category: string | null } }) | null> {
  const { data: mapping, error } = await supabase
    .from("broker_integration_accounts")
    .select(
      "id, user_id, connection_id, external_account_id, tradetraxs_account_id, sync_enabled, status"
    )
    .eq("id", mappingId)
    .eq("user_id", userId)
    .eq("connection_id", connectionId)
    .eq("provider", "tradovate")
    .maybeSingle()

  if (error || !mapping?.tradetraxs_account_id) return null
  if (!mapping.sync_enabled || mapping.status === "inactive") return null

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

export async function runTradovateAccountTradeSync(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  mappingId: string
): Promise<TradovateSyncSummary> {
  const mapping = await loadMapping(supabase, userId, connectionId, mappingId)
  if (!mapping) {
    return {
      ok: false,
      status: "error",
      fetched: 0,
      newExecutions: 0,
      duplicateExecutions: 0,
      tradesCreated: 0,
      tradesUpdated: 0,
      openPositions: 0,
      error: "Linked account not available.",
    }
  }

  const locked = await tryAcquireBrokerSyncLock(supabase, {
    mappingId,
    userId,
    connectionId,
  })
  if (!locked) {
    return {
      ok: false,
      status: "syncing",
      fetched: 0,
      newExecutions: 0,
      duplicateExecutions: 0,
      tradesCreated: 0,
      tradesUpdated: 0,
      openPositions: 0,
      error: "Sync already in progress.",
    }
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
    let maxExecutedAt: string | null = null as string | null

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
        if (!maxExecutedAt || ts > maxExecutedAt) {
          maxExecutedAt = ts
        }
      }

      contractIdsForResolve.add(String(fill.contractId))

      const { error: insertError } = await supabase
        .from("broker_integration_executions")
        .insert({
          user_id: userId,
          connection_id: connectionId,
          broker_integration_account_id: mappingId,
          provider: "tradovate",
          external_fill_id: fillIdNum,
          external_order_id:
            fill.orderId != null ? Number(fill.orderId) : null,
          external_contract_id: Number(fill.contractId),
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
        } else {
          throw new Error("execution_persist_failed")
        }
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
        .eq("broker_integration_account_id", mappingId)
        .eq("external_contract_id", Number(contractId))
    }

    const { data: storedExecutions, error: loadExecError } = await supabase
      .from("broker_integration_executions")
      .select(
        "external_fill_id, external_contract_id, side, quantity, price, executed_at"
      )
      .eq("broker_integration_account_id", mappingId)
      .order("executed_at", { ascending: true })
      .order("external_fill_id", { ascending: true })

    if (loadExecError || !storedExecutions) {
      throw new Error("execution_load_failed")
    }

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
      mappingId
    )

    const feeFillIds = [...new Set(completed.flatMap((t) => t.fillIds))]
    const feesByFillId = await fetchTradovateFillFeesForFillIds(
      supabase,
      userId,
      connectionId,
      feeFillIds
    )

    const { tradesCreated, tradesUpdated } = await upsertReconstructedBrokerTrades(
      supabase,
      {
        userId,
        connectionId,
        mappingId,
        account: mapping.account,
        completed,
        contracts,
        feesByFillId,
      }
    )

    const successAt = new Date().toISOString()
    await releaseBrokerSyncLock(supabase, mappingId, {
      lastSyncStatus: "success",
      lastSyncSuccessAt: successAt,
      lastSyncErrorCode: null,
      lastSyncErrorMessage: null,
      maxExternalFillId: maxFillId,
      maxExecutedAt: maxExecutedAt,
    })

    return {
      ok: true,
      status: "success",
      fetched: accountFills.length,
      newExecutions,
      duplicateExecutions,
      tradesCreated,
      tradesUpdated,
      openPositions: openByContract.size,
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

    await releaseBrokerSyncLock(supabase, mappingId, {
      lastSyncStatus: err instanceof TradovateApiError && err.code === "reconnect_required"
        ? "reconnect_required"
        : "error",
      lastSyncErrorCode: code,
      lastSyncErrorMessage: message,
    })

    return {
      ok: false,
      status: err instanceof TradovateApiError && err.code === "reconnect_required"
        ? "reconnect_required"
        : "error",
      fetched: 0,
      newExecutions: 0,
      duplicateExecutions: 0,
      tradesCreated: 0,
      tradesUpdated: 0,
      openPositions: 0,
      error: message,
    }
  }
}

export async function attachSyncViewsToBrokerAccounts<
  T extends { id: string }
>(supabase: SupabaseClient, accounts: T[]): Promise<
  (T & {
    lastSyncSuccessAt: string | null
    lastSyncStatus: string
  })[]
> {
  const views = await loadBrokerAccountSyncViews(
    supabase,
    accounts.map((a) => a.id)
  )
  return accounts.map((account) => {
    const sync = views.get(account.id)
    return {
      ...account,
      lastSyncSuccessAt: sync?.lastSyncSuccessAt ?? null,
      lastSyncStatus: sync?.lastSyncStatus ?? "never",
    }
  })
}
