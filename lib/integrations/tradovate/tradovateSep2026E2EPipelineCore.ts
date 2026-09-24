import { mergeAccountScopedTradovateFills } from "./tradovateFillAcquisitionCore.ts"
import type { TradovateFillAcquisitionStats } from "./tradovateFillAcquisitionCore.ts"
import { deriveTradovateImportAcquisitionStatus } from "./tradovateSyncCompleteness.ts"
import type { TradovateImportAcquisitionStatus } from "./tradovateSyncCompleteness.ts"
import { buildTradovateOrderAccountMap } from "./tradovateOrderAccountMap.ts"
import type { TradovateExecutionContractHint } from "./tradovateContractMeta.ts"
import type { TradovateFillRaw } from "./tradovateFillModels.ts"
import { tradovateSide } from "./tradovateFillModels.ts"
import {
  MGC_CONTRACT_ID,
  MNQ_CONTRACT_U6,
  MNQ_CONTRACT_Z6,
  TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
  tradovatePerformanceSep2026ReconstructionFills,
} from "./tradovatePerformanceSep2026Fixture.ts"
import {
  TRADOVATE_PERFORMANCE_EXPECTED,
  TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS,
} from "./tradovatePerformanceRegressionConstants.ts"
import {
  reconstructAllCompletedTrades,
  type ReconstructedLifecycleTrade,
  type ReconstructionFill,
} from "./tradeReconstruction.ts"
import { buildTradovateContractMetadataSnapshot } from "./tradovateContractResolutionCore.ts"
import {
  mergeTradovateContractMetaMaps,
  isValidResolvedTradovateSymbol,
  resolveBrokerTradeTicker,
  type BrokerContractMeta,
} from "./tradovateContractMeta.ts"
import {
  computeTradovateBrokerTradeFinancials,
} from "./tradovateBrokerTradeFinancials.ts"
import {
  lifecycleGrossPnl,
  reconcileTradovateFinancials,
  type TradovateFinancialReconciliationResult,
} from "./tradovateFinancialReconciliationCore.ts"
import {
  tradovatePerformanceSep2026FillContexts,
  tradovatePerformanceSep2026FillPairs,
} from "./tradovatePerformanceSep2026FillPairs.ts"
import type { NormalizedTradovateFillPair } from "./tradovateFillPairModels.ts"
import { dedupeTradovateFillPairsById } from "./tradovateFillPairModels.ts"
import {
  mergeTradovateFillFeeMaps,
  type TradovateFillFeeRecord,
} from "./tradovateFillFeeCoverageCore.ts"
import { mergeBrokerTradeFinancialFields } from "./brokerTradeAuthoritativeMerge.ts"
import { isNumericTradovateContractKey } from "./tradovateContractMeta.ts"

export type SimulatedLedgerExecution = {
  external_fill_id: string
  external_contract_id: string
  side: "Buy" | "Sell"
  quantity: number
  price: number
  executed_at: string
  symbol_root: string | null
  contract_name: string | null
  provider_metadata: Record<string, unknown>
}

export type Sep2026PipelineOptions = {
  includeRecoveryFills: boolean
  simulatePartialLdepsBatch?: boolean
  existingLedger?: SimulatedLedgerExecution[]
  feeRecords?: Map<string, TradovateFillFeeRecord>
  metadataResolutionFailed?: boolean
}

export type Sep2026PipelineResult = {
  acquisitionStatus: TradovateImportAcquisitionStatus
  acquisitionStats: TradovateFillAcquisitionStats
  accountFills: TradovateFillRaw[]
  ledger: SimulatedLedgerExecution[]
  newExecutions: number
  duplicateExecutions: number
  completed: ReconstructedLifecycleTrade[]
  contracts: Map<string, BrokerContractMeta>
  reconciliation: TradovateFinancialReconciliationResult
  tickers: string[]
  grossByContract: { mnq: number; mgc: number; overall: number }
  feeRecords: Map<string, TradovateFillFeeRecord>
}

function reconstructionFillToRaw(
  fill: ReconstructionFill,
  orderId: string
): TradovateFillRaw {
  return {
    id: fill.fillId,
    orderId,
    contractId: fill.contractId,
    timestamp: fill.timestamp,
    action: fill.action,
    qty: fill.qty,
    price: fill.price,
  }
}

function buildPerformanceContractMeta(): Map<string, BrokerContractMeta> {
  const snapshots = [
    buildTradovateContractMetadataSnapshot({
      contract: { id: MNQ_CONTRACT_U6, name: "MNQU6", contractMaturityId: "1" },
      maturity: { id: "1", productId: "10" },
      product: { id: "10", name: "MNQ", valuePerPoint: 2 },
    }),
    buildTradovateContractMetadataSnapshot({
      contract: { id: MNQ_CONTRACT_Z6, name: "MNQZ6", contractMaturityId: "2" },
      maturity: { id: "2", productId: "10" },
      product: { id: "10", name: "MNQ", valuePerPoint: 2 },
    }),
    buildTradovateContractMetadataSnapshot({
      contract: { id: MGC_CONTRACT_ID, name: "MGCV6", contractMaturityId: "3" },
      maturity: { id: "3", productId: "11" },
      product: { id: "11", name: "MGC", valuePerPoint: 10 },
    }),
  ]
  const resolved = new Map(
    snapshots.map((s) => [
      s.contractId,
      {
        contractId: s.contractId,
        contractName: s.contractName ?? "",
        symbolRoot: s.symbolRoot ?? "",
        valuePerPoint: s.valuePerPoint,
      },
    ])
  )
  return mergeTradovateContractMetaMaps(resolved, [])
}

export function buildSep2026AcquisitionInputs(includeRecoveryFills: boolean): {
  primaryLdeps: TradovateFillRaw[]
  supplementalList: TradovateFillRaw[]
  orderCount: number
} {
  const recovery = new Set<string>(TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS)
  const fills = tradovatePerformanceSep2026ReconstructionFills().filter(
    (row) => includeRecoveryFills || !recovery.has(row.fillId)
  )
  let orderSeq = 800000
  const allRaw = fills.map((f) => reconstructionFillToRaw(f, String(orderSeq++)))

  const primaryLdeps = includeRecoveryFills
    ? allRaw
    : allRaw.filter((f) => !recovery.has(String(f.id)))

  const supplementalList = includeRecoveryFills
    ? allRaw.filter((f) => !recovery.has(String(f.id)))
    : allRaw.filter((f) => !recovery.has(String(f.id)))

  const orders = buildTradovateOrderAccountMap(
    [...new Set(allRaw.map((f) => String(f.orderId)))].map((id) => ({
      id,
      accountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
    }))
  )

  return { primaryLdeps, supplementalList, orderCount: orders.size }
}

export function simulateAcquisitionStats(params: {
  accountId: string
  primaryLdeps: TradovateFillRaw[]
  supplementalList: TradovateFillRaw[]
  partialLdepsBatch: boolean
  orderCount: number
}): { stats: TradovateFillAcquisitionStats; acquisitionErrors: string[] } {
  const acquisitionErrors: string[] = []
  if (params.partialLdepsBatch) {
    acquisitionErrors.push("fill_ldeps:batch_0:simulated_partial_failure")
  }
  return {
    stats: {
      accountId: params.accountId,
      orderDepsCount: params.orderCount,
      orderIdsCount: params.orderCount,
      fillLdepsCount: params.primaryLdeps.length,
      fillListCount: params.supplementalList.length,
      mergedUniqueFillCount: 0,
      earliestFillTimestamp: null,
      latestFillTimestamp: null,
      fillLdepsBatchErrors: params.partialLdepsBatch ? 1 : 0,
      orderDepsFailed: false,
      fillListFailed: false,
      fillItemsRepairCount: 0,
      fillItemsRepairRequested: 0,
    },
    acquisitionErrors,
  }
}

export function persistFillsToSimulatedLedger(params: {
  accountFills: TradovateFillRaw[]
  existingLedger: SimulatedLedgerExecution[]
  contracts: Map<string, BrokerContractMeta>
}): {
  ledger: SimulatedLedgerExecution[]
  newExecutions: number
  duplicateExecutions: number
} {
  const byFillId = new Map(
    params.existingLedger.map((row) => [row.external_fill_id, row] as const)
  )
  let newExecutions = 0
  let duplicateExecutions = 0

  for (const fill of params.accountFills) {
    const fillId = String(fill.id)
    if (byFillId.has(fillId)) {
      duplicateExecutions += 1
      continue
    }
    const contractId = String(fill.contractId)
    const meta = params.contracts.get(contractId)
    const row: SimulatedLedgerExecution = {
      external_fill_id: fillId,
      external_contract_id: contractId,
      side: tradovateSide(fill),
      quantity: Number(fill.qty),
      price: Number(fill.price),
      executed_at: String(fill.timestamp),
      symbol_root: meta?.symbolRoot ?? null,
      contract_name: meta?.contractName ?? null,
      provider_metadata: {},
    }
    byFillId.set(fillId, row)
    newExecutions += 1
  }

  return {
    ledger: [...byFillId.values()].sort((a, b) =>
      a.executed_at.localeCompare(b.executed_at)
    ),
    newExecutions,
    duplicateExecutions,
  }
}

export function assertRecoveryFillsInLedger(ledger: SimulatedLedgerExecution[]): void {
  for (const fillId of TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS) {
    if (!ledger.some((r) => r.external_fill_id === fillId)) {
      throw new Error(`regression_fill_missing_in_ledger:${fillId}`)
    }
  }
}

export function validationFillPairsForLifecycles(
  completed: ReconstructedLifecycleTrade[]
): NormalizedTradovateFillPair[] {
  const synthetic: NormalizedTradovateFillPair[] = []
  let idx = 0
  for (const lc of completed) {
    if (lc.fillIds.length < 2) continue
    const buyPrice = lc.direction === "Long" ? lc.entryPrice : lc.exitPrice
    const sellPrice = lc.direction === "Long" ? lc.exitPrice : lc.entryPrice
    synthetic.push({
      id: `val-lc-${idx++}`,
      positionId: "perf",
      buyFillId: lc.fillIds[0]!,
      sellFillId: lc.fillIds[lc.fillIds.length - 1]!,
      qty: lc.contracts,
      buyPrice,
      sellPrice,
      active: true,
    })
  }
  return dedupeTradovateFillPairsById(synthetic)
}

export function performanceShapedFillPairsWithSyntheticLifecycles(
  completed: ReconstructedLifecycleTrade[]
): NormalizedTradovateFillPair[] {
  return dedupeTradovateFillPairsById([
    ...tradovatePerformanceSep2026FillPairs(),
    ...validationFillPairsForLifecycles(completed),
  ])
}

function sumGross(
  completed: ReconstructedLifecycleTrade[],
  contracts: Map<string, BrokerContractMeta>,
  filter: (t: ReconstructedLifecycleTrade) => boolean
): number {
  let total = 0
  for (const lc of completed.filter(filter)) {
    const { grossPnl } = lifecycleGrossPnl(lc, contracts.get(String(lc.contractId)))
    total += grossPnl ?? 0
  }
  return total
}

export function runTradovateSep2026Pipeline(
  options: Sep2026PipelineOptions
): Sep2026PipelineResult {
  const accountId = TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
  const { primaryLdeps, supplementalList, orderCount } = buildSep2026AcquisitionInputs(
    options.includeRecoveryFills
  )

  const orderAccountById = buildTradovateOrderAccountMap(
    [...new Set([...primaryLdeps, ...supplementalList].map((f) => String(f.orderId)))].map(
      (id) => ({ id, accountId })
    )
  )

  const accountFills = mergeAccountScopedTradovateFills({
    primaryFills: primaryLdeps,
    supplementalFills: supplementalList,
    targetAccountId: accountId,
    orderAccountById,
  })

  const { stats, acquisitionErrors } = simulateAcquisitionStats({
    accountId,
    primaryLdeps,
    supplementalList,
    partialLdepsBatch: options.simulatePartialLdepsBatch ?? false,
    orderCount,
  })
  stats.mergedUniqueFillCount = accountFills.length
  stats.orderDepsCount = orderCount
  stats.orderIdsCount = orderCount

  const acquisitionStatus = deriveTradovateImportAcquisitionStatus({
    stats,
    acquisitionErrors,
    mergedFillCount: accountFills.length,
  })

  let contracts = options.metadataResolutionFailed
    ? new Map<string, BrokerContractMeta>()
    : buildPerformanceContractMeta()

  if (!options.metadataResolutionFailed) {
    const hints: TradovateExecutionContractHint[] = accountFills.map((f) => ({
      external_contract_id: String(f.contractId),
      symbol_root: contracts.get(String(f.contractId))?.symbolRoot,
      contract_name: contracts.get(String(f.contractId))?.contractName,
    }))
    contracts = mergeTradovateContractMetaMaps(
      new Map(
        [...contracts.entries()].map(([id, m]) => [
          id,
          {
            contractId: id,
            contractName: m.contractName ?? "",
            symbolRoot: m.symbolRoot,
            valuePerPoint: m.valuePerPoint ?? null,
          },
        ])
      ),
      hints
    )
  }

  const persist = persistFillsToSimulatedLedger({
    accountFills,
    existingLedger: options.existingLedger ?? [],
    contracts,
  })

  if (options.includeRecoveryFills) {
    assertRecoveryFillsInLedger(persist.ledger)
  }

  const reconstructionFills: ReconstructionFill[] = persist.ledger.map((row) => ({
    fillId: row.external_fill_id,
    contractId: row.external_contract_id,
    action: row.side,
    qty: row.quantity,
    price: row.price,
    timestamp: row.executed_at,
  }))

  const { completed } = reconstructAllCompletedTrades(reconstructionFills, accountId)

  const fillsById = tradovatePerformanceSep2026FillContexts()
  for (const row of persist.ledger) {
    fillsById.set(row.external_fill_id, {
      fillId: row.external_fill_id,
      contractId: row.external_contract_id,
      tradeDate: row.executed_at.slice(0, 10),
    })
  }

  const fillPairs = options.includeRecoveryFills
    ? validationFillPairsForLifecycles(completed)
    : []

  const reconciliation = reconcileTradovateFinancials({
    accountId,
    fillPairs,
    fillsById,
    completed,
    contracts,
    insufficientFillPairData: false,
  })

  const feeRecords =
    options.feeRecords ??
    new Map<string, TradovateFillFeeRecord>()

  const tickers = completed.map((lc) => {
    const contractId = String(lc.contractId)
    return resolveBrokerTradeTicker({
      contract: contracts.get(contractId),
      contractId,
    })
  })

  return {
    acquisitionStatus,
    acquisitionStats: stats,
    accountFills,
    ledger: persist.ledger,
    newExecutions: persist.newExecutions,
    duplicateExecutions: persist.duplicateExecutions,
    completed,
    contracts,
    reconciliation,
    tickers,
    grossByContract: {
      mnq: sumGross(
        completed,
        contracts,
        (t) => t.contractId === MNQ_CONTRACT_U6 || t.contractId === MNQ_CONTRACT_Z6
      ),
      mgc: sumGross(completed, contracts, (t) => t.contractId === MGC_CONTRACT_ID),
      overall: sumGross(completed, contracts, () => true),
    },
    feeRecords,
  }
}

export function assertNoNumericTickers(tickers: string[]): void {
  for (const ticker of tickers) {
    if (isNumericTradovateContractKey(ticker) || !isValidResolvedTradovateSymbol(ticker)) {
      throw new Error(`numeric_or_invalid_ticker:${ticker}`)
    }
  }
}

export function simulateIncrementalBackfill(): {
  syncA: Sep2026PipelineResult
  syncB: Sep2026PipelineResult
} {
  const syncA = runTradovateSep2026Pipeline({ includeRecoveryFills: false })
  const syncB = runTradovateSep2026Pipeline({
    includeRecoveryFills: true,
    existingLedger: syncA.ledger,
  })
  return { syncA, syncB }
}

export function simulateResyncIdempotency(): {
  first: Sep2026PipelineResult
  second: Sep2026PipelineResult
} {
  const first = runTradovateSep2026Pipeline({ includeRecoveryFills: true })
  const second = runTradovateSep2026Pipeline({
    includeRecoveryFills: true,
    existingLedger: first.ledger,
  })
  return { first, second }
}

/** User-owned fields must survive broker resync patch merge. */
export const USER_OWNED_TRADE_FIELDS = [
  "notes",
  "psychology_notes",
  "public_description",
  "image_url",
  "strategy",
  "confidence",
  "emotion",
  "rr",
] as const

export function brokerPatchPreservesUserEnrichment(params: {
  existing: Record<string, unknown>
  incomingBroker: Record<string, unknown>
}): Record<string, unknown> {
  const patch = { ...params.incomingBroker }
  for (const key of USER_OWNED_TRADE_FIELDS) {
    if (params.existing[key] !== undefined) {
      patch[key] = params.existing[key]
    }
  }
  return patch
}

export function mergeFinancialsWithMetadataFailure(params: {
  existingPnL: number
  existingTicker: string
  incomingPnL: null
  incomingTicker: string
}): ReturnType<typeof mergeBrokerTradeFinancialFields> {
  return mergeBrokerTradeFinancialFields(params)
}

export function expectedPerformanceConstants() {
  return TRADOVATE_PERFORMANCE_EXPECTED
}

export function assertPerformanceEconomics(result: Sep2026PipelineResult): void {
  const exp = TRADOVATE_PERFORMANCE_EXPECTED
  if (result.completed.length !== exp.completedLifecycles) {
    throw new Error(`lifecycle_count:${result.completed.length}`)
  }
  if (Math.abs(result.grossByContract.mnq - exp.mnqGross) > 0.02) {
    throw new Error(`mnq_gross:${result.grossByContract.mnq}`)
  }
  if (Math.abs(result.grossByContract.mgc - exp.mgcGross) > 0.02) {
    throw new Error(`mgc_gross:${result.grossByContract.mgc}`)
  }
  if (Math.abs(result.grossByContract.overall - exp.overallGross) > 0.02) {
    throw new Error(`overall_gross:${result.grossByContract.overall}`)
  }
}

export function assertIncompletePerformanceEconomics(result: Sep2026PipelineResult): void {
  const exp = TRADOVATE_PERFORMANCE_EXPECTED
  if (result.completed.length !== exp.completedLifecyclesIncomplete) {
    throw new Error(`lifecycle_count:${result.completed.length}`)
  }
  if (Math.abs(result.grossByContract.mgc - exp.mgcGrossIncomplete) > 0.02) {
    throw new Error(`mgc_gross:${result.grossByContract.mgc}`)
  }
  if (Math.abs(result.grossByContract.overall - exp.overallGrossIncomplete) > 0.02) {
    throw new Error(`overall_gross:${result.grossByContract.overall}`)
  }
}

export function assertFeeSemantics(): void {
  const known: TradovateFillFeeRecord = {
    totals: { clearingFee: 1.5, exchangeFee: 0, nfaFee: 0, commission: 0 },
    availability: "KNOWN_VALUE",
  }
  const failed: TradovateFillFeeRecord = {
    totals: { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 },
    availability: "UNAVAILABLE",
  }
  const merged = mergeTradovateFillFeeMaps(
    new Map([["1", known]]),
    new Map([["1", failed]])
  )
  if (merged.get("1")!.availability !== "KNOWN_VALUE") {
    throw new Error("fee_downgrade")
  }

  const zeroKnown: TradovateFillFeeRecord = {
    totals: { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 },
    availability: "KNOWN_ZERO",
  }
  if (zeroKnown.availability !== "KNOWN_ZERO") throw new Error("known_zero")

  const lc = runTradovateSep2026Pipeline({ includeRecoveryFills: true }).completed[0]!
  const fin = computeTradovateBrokerTradeFinancials({
    lifecycle: lc,
    contract: buildPerformanceContractMeta().get(String(lc.contractId)),
    contractIdKey: String(lc.contractId),
    feesByFillId: new Map([
      [
        lc.fillIds[0]!,
        {
          totals: { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 },
          availability: "UNAVAILABLE",
        },
      ],
    ]),
  })
  if (fin.grossPnL == null) throw new Error("gross_missing")
  if (fin.netPnL != null) throw new Error("net_fabricated")
  if (fin.journalPnL == null || Math.abs(fin.journalPnL - (fin.grossPnL ?? 0)) > 0.001) {
    throw new Error("journal_pnl_should_use_gross_when_fees_unavailable")
  }
}
