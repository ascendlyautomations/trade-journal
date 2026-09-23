import type { SupabaseClient } from "@supabase/supabase-js"
import {
  releaseBrokerSyncLock,
  tryAcquireBrokerSyncLock,
} from "@/lib/integrations/brokerIntegrationSync"
import { TradovateApiError } from "@/lib/integrations/tradovate/tradovateApiClient"
import {
  tradovateFillStableId,
  tradovateSide,
} from "@/lib/integrations/tradovate/tradovateFillModels"
import {
  acquireTradovateFillsForAccount,
  logTradovateFillAcquisitionSummary,
} from "@/lib/integrations/tradovate/tradovateFillAcquisition"
import { acquireTradovateFillPairsForAccount } from "@/lib/integrations/tradovate/tradovateFillPairAcquisition"
import {
  reconcileTradovateFinancials,
  logTradovateFinancialReconciliation,
} from "@/lib/integrations/tradovate/tradovateFinancialReconciliationCore"
import type { TradovateLedgerFillContext } from "@/lib/integrations/tradovate/tradovateFillPairCore"
import {
  providerMetadataWithPersistedFillFee,
  resolveTradovateFillFeesForSync,
} from "@/lib/integrations/tradovate/tradovateFillFeeCoverage"
import {
  executionHintToMetadataSnapshot,
  logTradovateContractResolutionSummary,
  logTradovateContractUnresolved,
  mergeTradovateContractMetadataSnapshots,
  resolveTradovateContractMetadataBatch,
  resolvedSnapshotToMarketContract,
  unresolvedTradovateContractSnapshot,
  type TradovateContractResolutionStats,
} from "@/lib/integrations/tradovate/tradovateContractResolution"
import { computeTradovateBrokerTradeFinancials } from "@/lib/integrations/tradovate/tradovateBrokerTradeFinancials"
import {
  mergeTradovateProviderMetadataContractFields,
  readTradovateContractMetadataFromProviderMetadata,
} from "@/lib/integrations/tradovate/tradovateExecutionProviderMetadata"
import { upsertReconstructedBrokerTrades } from "@/lib/integrations/tradovate/persistBrokerTrades"
import {
  BROKER_EXECUTION_TRADOVATE_RECONSTRUCTION_SELECT,
  listBrokerExecutionsForExternalAccount,
  refreshBrokerExecutionRowAfterDuplicateInsert,
} from "@/lib/integrations/brokerExecutionIdentity"
import {
  aggregateTradovateExecutionContractHints,
  mergeTradovateContractMetaMaps,
  mergeTradovateExecutionMetadataFields,
  type TradovateExecutionContractHint,
} from "@/lib/integrations/tradovate/tradovateContractMeta"
import {
  buildTradovateImportPreviewTrades,
  type TradovateImportPreviewTrade,
} from "@/lib/integrations/tradovate/tradovateImportPreview"
import { logTradovateImportFlow } from "@/lib/integrations/tradovate/tradovateImportFlowLog"
import {
  filterPreviewsNotInBaseline,
  loadTradovateLifecycleKeysAtSyncStart,
} from "@/lib/integrations/tradovate/tradovateLifecycleKeys"
import {
  clearManualImportPreviewHold,
  isManualImportHoldActive,
  loadTradovateProviderSyncState,
  setManualImportPreviewHold,
} from "@/lib/integrations/tradovate/tradovateManualImportHold"
import {
  reconstructAllCompletedTrades,
  type ReconstructionFill,
} from "@/lib/integrations/tradovate/tradeReconstruction"
import { logTradovateSync } from "@/lib/integrations/tradovate/tradovateSyncLogger"
import {
  isTradovateTracedFillId,
  traceTradovateExecutionLedgerAfterPersist,
  traceTradovateExecutionPersist,
  traceTradovateFillListStage,
  traceTradovateFinalTradeIds,
  traceTradovateOrderAndFilterStage,
  traceTradovateReconstructionLoad,
  traceTradovateReconstructionResult,
} from "@/lib/integrations/tradovate/tradovateFillTrace"
import {
  deriveTradovateFeeCoverageStatus,
  deriveTradovateImportAcquisitionStatus,
} from "@/lib/integrations/tradovate/tradovateSyncCompleteness"
import {
  logTradovateSyncSummary,
  type TradovateSyncStageDurationsMs,
} from "@/lib/integrations/tradovate/tradovateSyncSummaryLog"
import type {
  TradovateSyncFailureCategory,
  TradovateSyncFailureStage,
} from "@/lib/integrations/tradovate/tradovateSyncLogger"

export type TradovateSyncTrigger = "manual" | "auto" | "reconnect" | "startup"

/** Manual import: preview reconstructs + financials without writing trades; import persists. */
export type TradovateSyncMode = "preview" | "import"

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
  /** Reconstructed trades with canonical ticker + dollar P&L for Review Imported Trades. */
  importPreviewTrades?: TradovateImportPreviewTrade[]
  existingLifecycleCountAtStart?: number
  previewEligibleCount?: number
  persistCalled?: boolean
  error?: string
  /** Machine code for clients/logs (iOS already decodes optionally). */
  errorCode?: string
  failureCategory?: TradovateSyncFailureCategory
  failureStage?: TradovateSyncFailureStage
  acquisitionStatus?: string
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
    importPreviewTrades: [],
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
    mode?: TradovateSyncMode
  }
): Promise<TradovateSyncSummary> {
  const started = Date.now()
  const { userId, connectionId, brokerIntegrationAccountId, trigger } = params
  const mode: TradovateSyncMode = params.mode ?? "import"
  let persistTrades = mode === "import"
  const autoOnly = trigger !== "manual"
  let existingLifecycleCountAtStart = 0
  let previewEligibleCount = 0
  let persistSkippedReason: string | undefined

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

  const existingLifecycleKeysAtStart = await loadTradovateLifecycleKeysAtSyncStart(
    supabase,
    { userId, mappingId: brokerIntegrationAccountId }
  )
  existingLifecycleCountAtStart = existingLifecycleKeysAtStart.size

  const providerSyncState = await loadTradovateProviderSyncState(
    supabase,
    brokerIntegrationAccountId
  )
  const manualImportHoldActive = isManualImportHoldActive(providerSyncState)
  if (
    persistTrades &&
    manualImportHoldActive &&
    !(trigger === "manual" && mode === "import")
  ) {
    persistTrades = false
    persistSkippedReason = "manual_import_hold"
  }

  const stageDurationsMs: TradovateSyncStageDurationsMs = {}
  let acquisitionStatus: ReturnType<typeof deriveTradovateImportAcquisitionStatus> =
    "IMPORT_SUCCESS_COMPLETE"
  let financialReconciliationStatus: import("@/lib/integrations/tradovate/tradovateFinancialReconciliationCore").TradovateFinancialReconciliationStatus =
    "INSUFFICIENT_FILLPAIR_DATA"
  let financialReconciliationDifference: number | null = null
  let feeCoverageStatus: ReturnType<typeof deriveTradovateFeeCoverageStatus> = "COMPLETE"
  let unresolvedContractCount = 0
  let feeBatchErrors: string[] = []

  try {
    const acquisitionStarted = Date.now()
    failureStage = "fill_list"
    const fillAcquisition = await acquireTradovateFillsForAccount(supabase, {
      userId,
      connectionId,
      targetAccountId,
      mappingId: brokerIntegrationAccountId,
      trigger,
    })
    stageDurationsMs.acquisition = Date.now() - acquisitionStarted
    acquisitionStatus = deriveTradovateImportAcquisitionStatus({
      stats: fillAcquisition.stats,
      acquisitionErrors: fillAcquisition.acquisitionErrors,
      mergedFillCount: fillAcquisition.accountFills.length,
    })

    traceTradovateFillListStage({
      targetAccountId,
      mappingId: brokerIntegrationAccountId,
      fillsRaw: fillAcquisition.supplementalFillList,
    })

    const accountFills = fillAcquisition.accountFills
    const orderAccountById = fillAcquisition.orderAccountById
    const accountFillIds = new Set(
      accountFills.map((fill) => tradovateFillStableId(fill))
    )

    traceTradovateOrderAndFilterStage({
      targetAccountId,
      fillsRaw: fillAcquisition.supplementalFillList,
      ordersRaw: [
        ...fillAcquisition.ordersFromDeps,
        ...fillAcquisition.ordersFromList,
      ],
      orderAccountById,
      missingOrderIds: [],
      hydratedOrders: [],
      accountFillIds,
    })

    let newExecutions = 0
    let duplicateExecutions = 0
    let maxFillId: number | null = null
    let maxExecutedAt: string | null = null

    const contractIdsForResolve = new Set<string>()

    const persistExecutionsStarted = Date.now()
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
          if (isTradovateTracedFillId(String(fillId))) {
            traceTradovateExecutionPersist({
              fillId: String(fillId),
              targetAccountId,
              outcome: {
                executionInsertAttempted: true,
                executionInsertSucceeded: false,
                executionInsertError: `23505:${insertError.message}`,
                executionAlreadyExists: true,
              },
            })
          }
        } else {
          if (isTradovateTracedFillId(String(fillId))) {
            traceTradovateExecutionPersist({
              fillId: String(fillId),
              targetAccountId,
              outcome: {
                executionInsertAttempted: true,
                executionInsertSucceeded: false,
                executionInsertError: `${insertError.code ?? "unknown"}:${insertError.message}`,
                executionAlreadyExists: false,
              },
            })
          }
          logTradovateSync("sync_error", {
            userId,
            connectionId,
            mappingId: brokerIntegrationAccountId,
            trigger,
            failureCategory: "execution_persistence_failure",
            failureStage: "persist_executions",
            errorCode: insertError.code ?? "execution_persist_failed",
            detail: insertError.message.slice(0, 200),
          })
          throw new Error("execution_persist_failed")
        }
      } else {
        newExecutions += 1
        if (isTradovateTracedFillId(String(fillId))) {
          traceTradovateExecutionPersist({
            fillId: String(fillId),
            targetAccountId,
            outcome: {
              executionInsertAttempted: true,
              executionInsertSucceeded: true,
              executionInsertError: null,
              executionAlreadyExists: false,
            },
          })
        }
      }
    }

    stageDurationsMs.persistExecutions = Date.now() - persistExecutionsStarted

    await traceTradovateExecutionLedgerAfterPersist({
      supabase,
      userId,
      mappingId: brokerIntegrationAccountId,
      targetAccountId,
    })

    logTradovateFillAcquisitionSummary({
      stats: fillAcquisition.stats,
      newLedgerExecutions: newExecutions,
      existingLedgerExecutions: duplicateExecutions,
    })

    const resolveContractsStarted = Date.now()
    failureStage = "resolve_contracts"
    const contractIdList = [...contractIdsForResolve]
    let executionHintsBeforeEnrich: TradovateExecutionContractHint[] = []
    const providerMetadataByContract = new Map<string, unknown>()
    if (contractIdList.length > 0) {
      const { data: executionRowsBeforeEnrich } = await supabase
        .from("broker_integration_executions")
        .select("external_contract_id, symbol_root, contract_name, provider_metadata")
        .eq("user_id", userId)
        .eq("provider", "tradovate")
        .eq("broker_integration_account_id", brokerIntegrationAccountId)
        .in("external_contract_id", contractIdList)
      executionHintsBeforeEnrich = (executionRowsBeforeEnrich ?? []).map((row) => {
        const persisted = readTradovateContractMetadataFromProviderMetadata(
          row.provider_metadata
        )
        const contractKey = String(row.external_contract_id)
        providerMetadataByContract.set(contractKey, row.provider_metadata)
        return {
          external_contract_id: contractKey,
          symbol_root: row.symbol_root,
          contract_name: row.contract_name,
          value_per_point: persisted.valuePerPoint,
          tick_size: persisted.tickSize,
          metadata_quality: persisted.metadataQuality,
        }
      })
    }
    const bestExistingHintByContract = new Map(
      aggregateTradovateExecutionContractHints(executionHintsBeforeEnrich).map(
        (hint) => [String(hint.external_contract_id).trim(), hint] as const
      )
    )

    const { cache: contractMetadataCache, stats: resolutionStatsBase } =
      await resolveTradovateContractMetadataBatch(
        supabase,
        userId,
        connectionId,
        contractIdList
      )

    const resolutionStats: TradovateContractResolutionStats = {
      ...resolutionStatsBase,
      persistedHintUsed: 0,
      localFallbackUsed: 0,
      numericTickerPrevented: 0,
    }

    for (const contractId of contractIdList) {
      const key = String(contractId).trim()
      const existingHint = bestExistingHintByContract.get(key)
      const hintSnapshot = existingHint
        ? executionHintToMetadataSnapshot(existingHint)
        : null
      if (hintSnapshot && hintSnapshot.metadataQuality === "PERSISTED_VALID_HINT") {
        resolutionStats.persistedHintUsed += 1
      }
      const mergedSnapshot = mergeTradovateContractMetadataSnapshots(
        hintSnapshot,
        contractMetadataCache.get(key) ?? unresolvedTradovateContractSnapshot(key)
      )

      if (mergedSnapshot.metadataQuality === "UNRESOLVED") {
        logTradovateContractUnresolved(mergedSnapshot)
      }

      const mergedFields = mergeTradovateExecutionMetadataFields(
        {
          symbol_root: existingHint?.symbol_root,
          contract_name: existingHint?.contract_name,
          value_per_point: existingHint?.value_per_point,
          tick_size: existingHint?.tick_size,
          metadata_quality: existingHint?.metadata_quality,
        },
        {
          symbol_root: mergedSnapshot.symbolRoot,
          contract_name: mergedSnapshot.contractName,
          value_per_point: mergedSnapshot.valuePerPoint,
          tick_size: mergedSnapshot.tickSize,
          metadata_quality: mergedSnapshot.metadataQuality,
        }
      )
      resolutionStats.numericTickerPrevented += mergedFields.numericTickerPrevented
        ? 1
        : 0

      const providerMetadata = mergeTradovateProviderMetadataContractFields(
        providerMetadataByContract.get(key),
        {
          valuePerPoint: mergedFields.value_per_point,
          tickSize: mergedFields.tick_size,
          metadataQuality: mergedFields.metadata_quality,
          productName: mergedSnapshot.productName,
        }
      )

      await supabase
        .from("broker_integration_executions")
        .update({
          contract_name: mergedFields.contract_name,
          symbol_root: mergedFields.symbol_root,
          provider_metadata: providerMetadata,
          updated_at: new Date().toISOString(),
        })
        .eq("broker_integration_account_id", brokerIntegrationAccountId)
        .eq("external_contract_id", key)
    }

    const contracts = new Map(
      [...contractMetadataCache.entries()].map(([id, snap]) => [
        id,
        resolvedSnapshotToMarketContract(snap),
      ])
    )
    unresolvedContractCount = resolutionStats.unresolved
    stageDurationsMs.resolveContracts = Date.now() - resolveContractsStarted

    const storedExecutions = await listBrokerExecutionsForExternalAccount(
      supabase,
      {
        userId,
        provider: "tradovate",
        externalAccountId: targetAccountId,
        fallbackMappingId: brokerIntegrationAccountId,
        select: BROKER_EXECUTION_TRADOVATE_RECONSTRUCTION_SELECT,
      }
    )

    const reconstructStarted = Date.now()
    failureStage = "reconstruct"
    const reconstructionFills: ReconstructionFill[] = storedExecutions.map((row) => ({
      fillId: String(row.external_fill_id),
      contractId: String(row.external_contract_id),
      timestamp: row.executed_at,
      action: row.side === "Sell" ? "Sell" : "Buy",
      qty: Number(row.quantity),
      price: Number(row.price),
    }))

    traceTradovateReconstructionLoad({
      targetAccountId,
      ledgerExecutionCount: storedExecutions.length,
      reconstructionExecutionCount: reconstructionFills.length,
      reconstructionFillIds: new Set(reconstructionFills.map((f) => f.fillId)),
    })

    const { completed, openByContract } = reconstructAllCompletedTrades(
      reconstructionFills,
      targetAccountId
    )

    traceTradovateReconstructionResult({
      targetAccountId,
      completed,
    })
    stageDurationsMs.reconstruct = Date.now() - reconstructStarted

    const feeFillIds = [...new Set(completed.flatMap((t) => t.fillIds))]
    const fetchFeesStarted = Date.now()
    failureStage = "fetch_fees"
    let feeRecordsByFillId = new Map<
      string,
      import("@/lib/integrations/tradovate/tradovateFillFeeCoverageCore").TradovateFillFeeRecord
    >()
    try {
      ;({ fees: feeRecordsByFillId, batchErrors: feeBatchErrors } =
        await resolveTradovateFillFeesForSync(supabase, {
          userId,
          connectionId,
          fillIds: feeFillIds,
          executionRows: storedExecutions.map((row) => ({
            external_fill_id: String(row.external_fill_id),
            provider_metadata: row.provider_metadata,
          })),
        }))
    } catch (feeErr) {
      if (!(feeErr instanceof TradovateApiError)) throw feeErr
    }
    stageDurationsMs.fetchFees = Date.now() - fetchFeesStarted
    feeCoverageStatus = deriveTradovateFeeCoverageStatus({
      fillIds: feeFillIds,
      feeBatchErrors,
      fees: feeRecordsByFillId,
    })

    for (const row of storedExecutions) {
      const fillId = String(row.external_fill_id)
      if (!feeFillIds.includes(fillId)) continue
      const record = feeRecordsByFillId.get(fillId)
      const providerMetadata = providerMetadataWithPersistedFillFee(
        row.provider_metadata,
        fillId,
        record
      )
      await supabase
        .from("broker_integration_executions")
        .update({
          provider_metadata: providerMetadata,
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", userId)
        .eq("provider", "tradovate")
        .eq("external_fill_id", fillId)
    }

    const executionHintsForPersist: TradovateExecutionContractHint[] =
      storedExecutions.map((row) => {
        const persisted = readTradovateContractMetadataFromProviderMetadata(
          row.provider_metadata
        )
        return {
          external_contract_id: String(row.external_contract_id),
          symbol_root: row.symbol_root,
          contract_name: row.contract_name,
          value_per_point: persisted.valuePerPoint,
          tick_size: persisted.tickSize,
          metadata_quality: persisted.metadataQuality,
        }
      })

    const contractsForPersist = mergeTradovateContractMetaMaps(
      contracts,
      executionHintsForPersist
    )

    for (const lifecycle of completed) {
      const contractIdKey = String(lifecycle.contractId).trim()
      const contract =
        contractsForPersist.get(contractIdKey) ??
        contractsForPersist.get(lifecycle.contractId)
      const fin = computeTradovateBrokerTradeFinancials({
        lifecycle,
        contract,
        contractIdKey,
        feesByFillId: feeRecordsByFillId,
      })
      if (fin.valuePerPointSource === "local_fallback") {
        resolutionStats.localFallbackUsed += 1
      }
    }
    logTradovateContractResolutionSummary(resolutionStats)

    const fillsByIdForValidation = new Map<string, TradovateLedgerFillContext>()
    for (const row of storedExecutions) {
      const fillId = String(row.external_fill_id)
      const ts = String(row.executed_at)
      fillsByIdForValidation.set(fillId, {
        fillId,
        contractId: String(row.external_contract_id),
        tradeDate: ts.slice(0, 10),
      })
    }

    const fillPairStarted = Date.now()
    let fillPairAcquisition = {
      fillPairs: [] as import("@/lib/integrations/tradovate/tradovateFillPairModels").NormalizedTradovateFillPair[],
      insufficientData: true,
      acquisitionErrors: [] as string[],
    }
    try {
      fillPairAcquisition = await acquireTradovateFillPairsForAccount(supabase, {
        userId,
        connectionId,
        targetAccountId,
        mappingId: brokerIntegrationAccountId,
        trigger,
        accountFills: fillAcquisition.accountFills,
      })
    } catch {
      fillPairAcquisition = {
        fillPairs: [],
        insufficientData: true,
        acquisitionErrors: ["fill_pair_acquisition_failed"],
      }
    }

    const financialReconciliation = reconcileTradovateFinancials({
      accountId: targetAccountId,
      fillPairs: fillPairAcquisition.fillPairs,
      fillsById: fillsByIdForValidation,
      completed,
      contracts: contractsForPersist,
      insufficientFillPairData: fillPairAcquisition.insufficientData,
    })
    logTradovateFinancialReconciliation(financialReconciliation)
    financialReconciliationStatus = financialReconciliation.status
    financialReconciliationDifference = financialReconciliation.difference
    stageDurationsMs.fillPairValidation = Date.now() - fillPairStarted

    const allPreviews = buildTradovateImportPreviewTrades({
      completed,
      contracts: contractsForPersist,
      feesByFillId: feeRecordsByFillId,
    })
    const importablePreviews = filterPreviewsNotInBaseline(
      allPreviews,
      existingLifecycleKeysAtStart
    )
    previewEligibleCount = importablePreviews.length

    if (trigger === "manual" && mode === "preview") {
      if (importablePreviews.length > 0) {
        await setManualImportPreviewHold(
          supabase,
          brokerIntegrationAccountId,
          importablePreviews.map((p) => p.lifecycleKey)
        )
      } else {
        await clearManualImportPreviewHold(supabase, brokerIntegrationAccountId)
      }
    }

    let tradesCreated = 0
    let tradesUpdated = 0
    let newTradeIds: string[] = []
    let updatedTradeIds: string[] = []
    let tradesWithPnL = 0
    let tradesWithoutPnL = 0
    let numericTickersPersisted = 0

    if (persistTrades) {
      const persistTradesStarted = Date.now()
      failureStage = "persist_trades"
      ;({
        tradesCreated,
        tradesUpdated,
        newTradeIds,
        updatedTradeIds,
        tradesWithPnL,
        tradesWithoutPnL,
        numericTickersPersisted,
      } = await upsertReconstructedBrokerTrades(
        supabase,
        {
          userId,
          connectionId,
          mappingId: brokerIntegrationAccountId,
          externalBrokerAccountId: targetAccountId,
          account: mapping.account,
          completed,
          contracts: contractsForPersist,
          feesByFillId: feeRecordsByFillId,
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
      }))
      stageDurationsMs.persistTrades = Date.now() - persistTradesStarted
    }

    await traceTradovateFinalTradeIds({
      supabase,
      userId,
      targetAccountId,
      completed,
    })

    if (trigger === "manual" && mode === "import") {
      await clearManualImportPreviewHold(supabase, brokerIntegrationAccountId)
    }

    logTradovateImportFlow({
      mode,
      trigger,
      mappingId: brokerIntegrationAccountId,
      persistCalled: persistTrades,
      lifecyclesBuilt: completed.length,
      existingLifecycleCountAtStart,
      previewEligibleCount,
      importPreviewTradesCount: importablePreviews.length,
      inserted: tradesCreated,
      updated: tradesUpdated,
      manualImportHoldActive,
      persistSkippedReason,
    })

    const successAt = new Date().toISOString()
    const durationMs = Date.now() - started
    const syncLockStatus =
      acquisitionStatus === "IMPORT_SUCCESS_PARTIAL" ? "partial" : "success"
    let lifecycleGrossTotal: number | null = null
    for (const lifecycle of completed) {
      const contractIdKey = String(lifecycle.contractId).trim()
      const contract =
        contractsForPersist.get(contractIdKey) ??
        contractsForPersist.get(lifecycle.contractId)
      const fin = computeTradovateBrokerTradeFinancials({
        lifecycle,
        contract,
        contractIdKey,
        feesByFillId: feeRecordsByFillId,
      })
      if (fin.grossPnL != null) {
        lifecycleGrossTotal = (lifecycleGrossTotal ?? 0) + fin.grossPnL
      }
    }

    logTradovateSyncSummary({
      accountId: targetAccountId,
      acquisitionStatus,
      orders: fillAcquisition.stats.orderIdsCount,
      dependencyFills: fillAcquisition.stats.fillLdepsCount,
      supplementalFills: fillAcquisition.stats.fillListCount,
      uniqueFills: fillAcquisition.stats.mergedUniqueFillCount,
      ledgerExecutions: storedExecutions.length,
      newExecutions,
      existingExecutions: duplicateExecutions,
      completedLifecycles: completed.length,
      tradesInserted: tradesCreated,
      tradesUpdated: tradesUpdated,
      unresolvedContracts: unresolvedContractCount,
      fillPairStatus: financialReconciliationStatus,
      fillPairDifference: financialReconciliationDifference,
      feeCoverage: feeCoverageStatus,
      grossPnl: lifecycleGrossTotal,
      durationMs,
      stageDurationsMs,
    })

    await releaseBrokerSyncLock(supabase, brokerIntegrationAccountId, {
      lastSyncStatus: syncLockStatus,
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
      tradesWithPnL,
      tradesWithoutPnL,
      tradesBuilt: completed.length,
      numericTickersPersisted,
    })

    return {
      ok: acquisitionStatus !== "IMPORT_FAILED",
      status: syncLockStatus,
      acquisitionStatus,
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
      importPreviewTrades: importablePreviews,
      existingLifecycleCountAtStart,
      previewEligibleCount,
      persistCalled: persistTrades,
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
