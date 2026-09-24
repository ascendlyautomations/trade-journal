import type { BrokerContractMeta } from "./tradovateContractMeta.ts"
import { computeFuturesGrossPnl } from "./tradeReconstruction.ts"
import type { ReconstructedLifecycleTrade } from "./tradeReconstruction.ts"
import { resolveEffectiveValuePerPoint } from "./futuresValuePerPointFallback.ts"
import { normalizedFuturesRootFromContractMeta } from "./tradovateContractMeta.ts"
import {
  computeTradovateFillPairGrossPnl,
  contractIdForFillPair,
  tradeDateForFillPair,
  type TradovateLedgerFillContext,
} from "./tradovateFillPairCore.ts"
import type { NormalizedTradovateFillPair } from "./tradovateFillPairModels.ts"

export type TradovateFinancialReconciliationStatus =
  | "MATCH"
  | "MISMATCH"
  | "INSUFFICIENT_FILLPAIR_DATA"
  | "INSUFFICIENT_FILLPAIR_COVERAGE"
  | "UNRESOLVED_METADATA"

export type TradovateFinancialReconciliationGroupDiagnostic = {
  contractId: string
  tradeDate: string
  fillPairPnl: number
  lifecyclePnl: number
  difference: number
}

export type TradovateFinancialReconciliationResult = {
  accountId: string
  fillPairCount: number
  lifecycleCount: number
  fillPairGrossPnl: number | null
  lifecycleGrossPnl: number | null
  difference: number | null
  status: TradovateFinancialReconciliationStatus
  groupDiagnostics: TradovateFinancialReconciliationGroupDiagnostic[]
}

export const TRADOVATE_FINANCIAL_RECONCILIATION_TOLERANCE = 0.02

function tradeDateFromIso(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ""
  return d.toISOString().slice(0, 10)
}

export function lifecycleGrossPnl(
  lifecycle: ReconstructedLifecycleTrade,
  contract?: BrokerContractMeta | null
): { grossPnl: number | null; unresolvedMetadata: boolean } {
  const root = normalizedFuturesRootFromContractMeta(contract)
  const vpp = resolveEffectiveValuePerPoint({
    symbolRoot: root ?? "",
    contractValuePerPoint: contract?.valuePerPoint ?? null,
  })
  if (vpp == null || vpp <= 0 || !root) {
    return { grossPnl: null, unresolvedMetadata: true }
  }
  return {
    grossPnl: computeFuturesGrossPnl(
      lifecycle.direction,
      lifecycle.entryPrice,
      lifecycle.exitPrice,
      lifecycle.contracts,
      vpp
    ),
    unresolvedMetadata: false,
  }
}

export function reconcileTradovateFinancials(params: {
  accountId: string
  fillPairs: NormalizedTradovateFillPair[]
  fillsById: Map<string, TradovateLedgerFillContext>
  completed: ReconstructedLifecycleTrade[]
  contracts: Map<string, BrokerContractMeta>
  insufficientFillPairData: boolean
  tolerance?: number
}): TradovateFinancialReconciliationResult {
  const tolerance = params.tolerance ?? TRADOVATE_FINANCIAL_RECONCILIATION_TOLERANCE
  const groupDiagnostics: TradovateFinancialReconciliationGroupDiagnostic[] = []

  if (params.fillPairs.length === 0 && params.completed.length > 0) {
    return {
      accountId: params.accountId,
      fillPairCount: 0,
      lifecycleCount: params.completed.length,
      fillPairGrossPnl: null,
      lifecycleGrossPnl: null,
      difference: null,
      status: params.insufficientFillPairData
        ? "INSUFFICIENT_FILLPAIR_DATA"
        : "INSUFFICIENT_FILLPAIR_COVERAGE",
      groupDiagnostics,
    }
  }

  let fillPairUnresolved = false
  let lifecycleUnresolved = false
  let fillPairGrossTotal = 0
  let lifecycleGrossTotal = 0

  const fillPairByGroup = new Map<string, number>()
  for (const pair of params.fillPairs) {
    const contractId = contractIdForFillPair(pair, params.fillsById)
    if (!contractId) {
      fillPairUnresolved = true
      continue
    }
    const tradeDate = tradeDateForFillPair(pair, params.fillsById)
    if (!tradeDate) {
      fillPairUnresolved = true
      continue
    }
    const { grossPnl, unresolvedMetadata } = computeTradovateFillPairGrossPnl({
      pair,
      contract: params.contracts.get(contractId),
      contractId,
    })
    if (unresolvedMetadata || grossPnl == null) {
      fillPairUnresolved = true
      continue
    }
    fillPairGrossTotal += grossPnl
    const key = `${contractId}:${tradeDate}`
    fillPairByGroup.set(key, (fillPairByGroup.get(key) ?? 0) + grossPnl)
  }

  const lifecycleByGroup = new Map<string, number>()
  for (const lifecycle of params.completed) {
    const contractId = String(lifecycle.contractId).trim()
    const tradeDate = tradeDateFromIso(lifecycle.exitTime)
    const { grossPnl, unresolvedMetadata } = lifecycleGrossPnl(
      lifecycle,
      params.contracts.get(contractId)
    )
    if (unresolvedMetadata || grossPnl == null) {
      lifecycleUnresolved = true
      continue
    }
    lifecycleGrossTotal += grossPnl
    const key = `${contractId}:${tradeDate}`
    lifecycleByGroup.set(key, (lifecycleByGroup.get(key) ?? 0) + grossPnl)
  }

  if (fillPairUnresolved || lifecycleUnresolved) {
    return {
      accountId: params.accountId,
      fillPairCount: params.fillPairs.length,
      lifecycleCount: params.completed.length,
      fillPairGrossPnl: fillPairUnresolved ? null : fillPairGrossTotal,
      lifecycleGrossPnl: lifecycleUnresolved ? null : lifecycleGrossTotal,
      difference: null,
      status: "UNRESOLVED_METADATA",
      groupDiagnostics,
    }
  }

  const lifecycleOnlyGroups = [...lifecycleByGroup.keys()].filter(
    (key) => !fillPairByGroup.has(key)
  )
  const coveredLifecycleKeys = [...lifecycleByGroup.keys()].filter((key) =>
    fillPairByGroup.has(key)
  )

  if (
    lifecycleOnlyGroups.length > 0 &&
    fillPairByGroup.size > 0 &&
    fillPairByGroup.size < lifecycleByGroup.size
  ) {
    return {
      accountId: params.accountId,
      fillPairCount: params.fillPairs.length,
      lifecycleCount: params.completed.length,
      fillPairGrossPnl: fillPairGrossTotal,
      lifecycleGrossPnl: lifecycleGrossTotal,
      difference: null,
      status: "INSUFFICIENT_FILLPAIR_COVERAGE",
      groupDiagnostics,
    }
  }

  let coveredFillPairTotal = 0
  let coveredLifecycleTotal = 0
  for (const key of coveredLifecycleKeys) {
    coveredFillPairTotal += fillPairByGroup.get(key) ?? 0
    coveredLifecycleTotal += lifecycleByGroup.get(key) ?? 0
  }

  for (const key of coveredLifecycleKeys) {
    const [contractId, tradeDate] = key.split(":")
    const fillPairPnl = fillPairByGroup.get(key) ?? 0
    const lifecyclePnl = lifecycleByGroup.get(key) ?? 0
    const groupDiff = fillPairPnl - lifecyclePnl
    if (Math.abs(groupDiff) > tolerance) {
      groupDiagnostics.push({
        contractId: contractId ?? "",
        tradeDate: tradeDate ?? "",
        fillPairPnl,
        lifecyclePnl,
        difference: groupDiff,
      })
    }
  }

  const compareFillTotal =
    coveredLifecycleKeys.length > 0 ? coveredFillPairTotal : fillPairGrossTotal
  const compareLifecycleTotal =
    coveredLifecycleKeys.length > 0 ? coveredLifecycleTotal : lifecycleGrossTotal
  const difference = compareFillTotal - compareLifecycleTotal

  const status =
    Math.abs(difference) <= tolerance && groupDiagnostics.length === 0
      ? "MATCH"
      : "MISMATCH"

  return {
    accountId: params.accountId,
    fillPairCount: params.fillPairs.length,
    lifecycleCount: params.completed.length,
    fillPairGrossPnl: fillPairGrossTotal,
    lifecycleGrossPnl: lifecycleGrossTotal,
    difference,
    status,
    groupDiagnostics,
  }
}

export function logTradovateFinancialReconciliation(
  result: TradovateFinancialReconciliationResult
): void {
  console.info(
    [
      "[TradovateFinancialReconciliation]",
      `accountId=${result.accountId}`,
      `fillPairCount=${result.fillPairCount}`,
      `lifecycleCount=${result.lifecycleCount}`,
      `fillPairGrossPnl=${result.fillPairGrossPnl ?? "null"}`,
      `lifecycleGrossPnl=${result.lifecycleGrossPnl ?? "null"}`,
      `difference=${result.difference ?? "null"}`,
      `status=${result.status}`,
    ].join(" ")
  )
  for (const group of result.groupDiagnostics) {
    console.info(
      [
        "[TradovateFinancialReconciliation]",
        "groupMismatch",
        `contract=${group.contractId}`,
        `tradeDate=${group.tradeDate}`,
        `fillPairPnl=${group.fillPairPnl}`,
        `lifecyclePnl=${group.lifecyclePnl}`,
        `difference=${group.difference}`,
      ].join(" ")
    )
  }
}
