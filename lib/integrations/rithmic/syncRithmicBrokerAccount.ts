import type { SupabaseClient } from "@supabase/supabase-js"
import {
  releaseBrokerSyncLock,
  tryAcquireBrokerSyncLock,
} from "@/lib/integrations/brokerIntegrationSync"
import {
  BROKER_EXECUTION_RITHMIC_RECONSTRUCTION_SELECT,
  listBrokerExecutionsForExternalAccount,
  refreshBrokerExecutionRowAfterDuplicateInsert,
} from "@/lib/integrations/brokerExecutionIdentity"
import { upsertReconstructedBrokerTrades } from "@/lib/integrations/tradovate/persistBrokerTrades"
import {
  reconstructAllCompletedTrades,
  type ReconstructionFill,
} from "@/lib/integrations/tradovate/tradeReconstruction"
import { resolveRithmicSessionConfigForOperation } from "@/lib/integrations/rithmic/loadRithmicConnectionSessionConfig"
import { withRithmicOrderPlantSession } from "@/lib/integrations/rithmic/rithmicImportSession"
import { markBrokerConnectionReconnectRequired } from "@/lib/integrations/brokerIntegrationConnection"
import {
  mergeRithmicFillCheckpoint,
  normalizeRithmicSymbolRoot,
  parseRithmicExternalAccountParts,
  readRithmicFillCheckpoint,
  stableRithmicFillId,
  type RithmicFillCheckpoint,
} from "@/lib/integrations/rithmic/rithmicFillModels"
import { logRithmicDiagnostic } from "@/lib/integrations/rithmic/rithmicSyncLogger"
import type { BrokerContractMeta } from "@/lib/integrations/tradovate/persistBrokerTrades"

export type RithmicSyncTrigger = "manual"

export type RithmicSyncSummary = {
  ok: boolean
  status: string
  trigger: RithmicSyncTrigger
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
  errorCode?: string
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

async function loadRithmicMappingForSync(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  brokerIntegrationAccountId: string
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
    .eq("provider", "rithmic")
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

function emptySummary(patch: Partial<RithmicSyncSummary>): RithmicSyncSummary {
  return {
    ok: false,
    status: "error",
    trigger: "manual",
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

export async function syncRithmicBrokerAccount(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    brokerIntegrationAccountId: string
    trigger?: RithmicSyncTrigger
    transientPassword?: string | null
  }
): Promise<RithmicSyncSummary> {
  const started = Date.now()
  const { userId, connectionId, brokerIntegrationAccountId } = params

  const mapping = await loadRithmicMappingForSync(
    supabase,
    userId,
    connectionId,
    brokerIntegrationAccountId
  )
  if (!mapping) {
    return emptySummary({ error: "Linked Rithmic account not available." })
  }

  const targetAccountId = String(mapping.external_account_id)

  const accountParts = parseRithmicExternalAccountParts(targetAccountId)
  if (!accountParts) {
    return emptySummary({ error: "Invalid Rithmic account identity on mapping." })
  }

  const locked = await tryAcquireBrokerSyncLock(supabase, {
    mappingId: brokerIntegrationAccountId,
    userId,
    connectionId,
  })
  if (!locked) {
    return emptySummary({ status: "syncing", error: "Sync already in progress." })
  }

  const { data: syncRow } = await supabase
    .from("broker_integration_account_sync")
    .select("provider_sync_state")
    .eq("broker_integration_account_id", brokerIntegrationAccountId)
    .maybeSingle()

  const checkpoint = readRithmicFillCheckpoint(
    (syncRow?.provider_sync_state as Record<string, unknown> | null) ?? null
  )

  const finishIndex = Math.floor(Date.now() / 1000)
  const startIndex = checkpoint ? Math.max(0, checkpoint.lastSsboe - 1) : 0

  const sessionResolved = await resolveRithmicSessionConfigForOperation(supabase, {
    userId,
    connectionId,
    transientPassword: params.transientPassword,
  })
  if (!sessionResolved.ok) {
    await releaseBrokerSyncLock(supabase, brokerIntegrationAccountId, {
      lastSyncStatus: "error",
      lastSyncErrorCode: sessionResolved.code,
      lastSyncErrorMessage: sessionResolved.userMessage,
    })
    return emptySummary({
      error: sessionResolved.userMessage,
      errorCode: sessionResolved.code,
    })
  }
  const sessionConfig = sessionResolved.config

  try {
    const { fills, rpCode } = await withRithmicOrderPlantSession(async (client) => {
      return client.requestShowFillHistory({
        fcmId: accountParts.fcmId,
        ibId: accountParts.ibId,
        accountId: accountParts.accountId,
        indexFormat: "ssboe",
        startIndex,
        finishIndex,
      })
    }, sessionConfig)

    if (rpCode[0] !== "0") {
      throw new Error(`rithmic_fill_history_rp_code:${rpCode.join(",")}`)
    }

    let newExecutions = 0
    let duplicateExecutions = 0
    let maxExecutedAt: string | null = null
    let maxFillKey: string | null = null
    let nextCheckpoint: RithmicFillCheckpoint | null = checkpoint

    for (const row of fills) {
      const externalFillId = stableRithmicFillId(row)
      const executedAt = row.executedAt
      if (!maxExecutedAt || executedAt > maxExecutedAt) maxExecutedAt = executedAt
      if (!maxFillKey || externalFillId > maxFillKey) maxFillKey = externalFillId

      const { error: insertError } = await supabase.from("broker_integration_executions").insert({
        user_id: userId,
        connection_id: connectionId,
        broker_integration_account_id: brokerIntegrationAccountId,
        provider: "rithmic",
        external_fill_id: externalFillId,
        external_order_id: row.sequenceNumber,
        external_contract_id: `${row.exchange}:${row.symbol}`,
        contract_name: row.symbol,
        symbol_root: normalizeRithmicSymbolRoot(row.symbol),
        side: row.side,
        quantity: row.quantity,
        price: row.price,
        executed_at: executedAt,
        provider_metadata: {
          fill_id: row.fillId,
          fcm_id: row.fcmId,
          ib_id: row.ibId,
          account_id: row.accountId,
          exchange: row.exchange,
          raw_symbol: row.rawSymbol,
          transaction_type: row.transactionTypeRaw,
          ssboe: row.ssboe,
          usecs: row.usecs,
          sequence_number: row.sequenceNumber,
        },
        updated_at: new Date().toISOString(),
      })

      if (insertError) {
        if (insertError.code === "23505") {
          duplicateExecutions += 1
          await refreshBrokerExecutionRowAfterDuplicateInsert(supabase, {
            userId,
            provider: "rithmic",
            externalFillId,
            connectionId,
            brokerIntegrationAccountId,
          })
        } else throw new Error("execution_persist_failed")
      } else {
        newExecutions += 1
      }

      if (row.ssboe != null) {
        const candidate: RithmicFillCheckpoint = {
          indexFormat: "ssboe",
          lastSsboe: row.ssboe,
          lastUsecs: row.usecs ?? 0,
        }
        if (
          !nextCheckpoint ||
          candidate.lastSsboe > nextCheckpoint.lastSsboe ||
          (candidate.lastSsboe === nextCheckpoint.lastSsboe &&
            candidate.lastUsecs > nextCheckpoint.lastUsecs)
        ) {
          nextCheckpoint = candidate
        }
      }
    }

    const storedExecutions = await listBrokerExecutionsForExternalAccount(
      supabase,
      {
        userId,
        provider: "rithmic",
        externalAccountId: targetAccountId,
        fallbackMappingId: brokerIntegrationAccountId,
        select: BROKER_EXECUTION_RITHMIC_RECONSTRUCTION_SELECT,
      }
    )

    const reconstructionFills: ReconstructionFill[] = storedExecutions
      .map((row) => ({
        fillId: String(row.external_fill_id),
        contractId: String(row.external_contract_id),
        timestamp: row.executed_at,
        action: row.side === "Sell" ? ("Sell" as const) : ("Buy" as const),
        qty: Number(row.quantity),
        price: Number(row.price),
      }))
      .filter((f) => f.qty > 0)

    const { completed, openByContract } = reconstructAllCompletedTrades(
      reconstructionFills,
      targetAccountId,
      { lifecycleProvider: "rithmic" }
    )

    const contracts = new Map<string, BrokerContractMeta>()
    for (const row of storedExecutions) {
      const cid = String(row.external_contract_id)
      if (!contracts.has(cid)) {
        contracts.set(cid, {
          symbolRoot:
            (row.symbol_root as string | null) ??
            normalizeRithmicSymbolRoot(String(row.contract_name ?? cid)),
          contractName: row.contract_name,
          valuePerPoint: null,
        })
      }
    }

    const { tradesCreated, tradesUpdated, newTradeIds, updatedTradeIds } =
      await upsertReconstructedBrokerTrades(supabase, {
        userId,
        connectionId,
        mappingId: brokerIntegrationAccountId,
        externalBrokerAccountId: targetAccountId,
        account: mapping.account,
        completed,
        contracts,
        feesByFillId: new Map(),
        importSource: "rithmic",
      })

    const successAt = new Date().toISOString()
    const durationMs = Date.now() - started

    if (newExecutions > 0 && nextCheckpoint) {
      await releaseBrokerSyncLock(supabase, brokerIntegrationAccountId, {
        lastSyncStatus: "success",
        lastSyncSuccessAt: successAt,
        lastSyncErrorCode: null,
        lastSyncErrorMessage: null,
        maxExternalFillId: maxFillKey,
        maxExecutedAt,
        providerSyncState: mergeRithmicFillCheckpoint(
          (syncRow?.provider_sync_state as Record<string, unknown> | null) ?? null,
          nextCheckpoint
        ),
      })
    } else {
      await releaseBrokerSyncLock(supabase, brokerIntegrationAccountId, {
        lastSyncStatus: "success",
        lastSyncSuccessAt: successAt,
        lastSyncErrorCode: null,
        lastSyncErrorMessage: null,
        maxExternalFillId: maxFillKey,
        maxExecutedAt,
        providerSyncState: nextCheckpoint
          ? mergeRithmicFillCheckpoint(
              (syncRow?.provider_sync_state as Record<string, unknown> | null) ?? null,
              nextCheckpoint
            )
          : undefined,
      })
    }

    logRithmicDiagnostic("rithmic_import_success", {
      mappingId: brokerIntegrationAccountId,
      fetched: fills.length,
      newExecutions,
      tradesCreated,
    })

    return {
      ok: true,
      status: "success",
      trigger: "manual",
      fetched: fills.length,
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
    const message = err instanceof Error ? err.message : "Could not import Rithmic trades."
    if (
      message.includes("rithmic_login_failed") ||
      message.includes("rithmic_login_info_failed") ||
      message.includes("rithmic_system_info_failed") ||
      message.includes("rithmic_system_name_required")
    ) {
      await markBrokerConnectionReconnectRequired(supabase, connectionId, userId)
    }
    await releaseBrokerSyncLock(supabase, brokerIntegrationAccountId, {
      lastSyncStatus: "error",
      lastSyncErrorCode: "rithmic_import_failed",
      lastSyncErrorMessage: message.slice(0, 500),
    })
    logRithmicDiagnostic("rithmic_error", { message: message.slice(0, 120) })
    return emptySummary({
      error: message,
      durationMs: Date.now() - started,
    })
  }
}
