import { normalizeFuturesSymbol } from "../../normalizeFuturesSymbol.ts"
import type {
  TradovateContractMaturityRaw,
  TradovateContractRaw,
  TradovateProductRaw,
} from "./tradovateFillModels.ts"
import {
  isNumericTradovateContractKey,
  isValidResolvedTradovateSymbol,
  type BrokerContractMeta,
  type TradovateExecutionContractHint,
} from "./tradovateContractMeta.ts"
import {
  metadataQualityRank,
  type TradovateMetadataQuality,
} from "./tradovateMetadataQuality.ts"

export type { TradovateMetadataQuality } from "./tradovateMetadataQuality.ts"
export { metadataQualityRank } from "./tradovateMetadataQuality.ts"

export type TradovateContractMetadataSnapshot = {
  contractId: string
  contractName: string | null
  contractMaturityId: string | null
  productId: string | null
  productName: string | null
  symbolRoot: string | null
  valuePerPoint: number | null
  tickSize: number | null
  metadataQuality: TradovateMetadataQuality
  resolutionStage: string
  unresolvedReason: string | null
}

export type TradovateContractResolutionStats = {
  contractIds: number
  contractResolved: number
  maturityResolved: number
  productResolved: number
  productVppResolved: number
  persistedHintUsed: number
  localFallbackUsed: number
  unresolved: number
  numericTickerPrevented: number
}

export type ResolvedTradovateContractSnapshot = {
  contractId: string
  contractName: string
  symbolRoot: string
  valuePerPoint: number | null
}

export function emptyTradovateContractResolutionStats(
  contractIdCount: number
): TradovateContractResolutionStats {
  return {
    contractIds: contractIdCount,
    contractResolved: 0,
    maturityResolved: 0,
    productResolved: 0,
    productVppResolved: 0,
    persistedHintUsed: 0,
    localFallbackUsed: 0,
    unresolved: 0,
    numericTickerPrevented: 0,
  }
}

function finitePositive(n: unknown): number | null {
  if (n == null) return null
  const v = Number(n)
  return Number.isFinite(v) && v > 0 ? v : null
}

function symbolRootFromNames(productName: string | null, contractName: string | null): string | null {
  for (const raw of [productName, contractName]) {
    const trimmed = String(raw ?? "").trim()
    if (!trimmed || isNumericTradovateContractKey(trimmed)) continue
    const normalized = normalizeFuturesSymbol(trimmed)
    if (normalized && isValidResolvedTradovateSymbol(normalized)) return normalized
    if (isValidResolvedTradovateSymbol(trimmed)) return trimmed
  }
  return null
}

export function buildTradovateContractMetadataSnapshot(params: {
  contract: TradovateContractRaw
  maturity?: TradovateContractMaturityRaw | null
  product?: TradovateProductRaw | null
}): TradovateContractMetadataSnapshot {
  const contractId = String(params.contract.id ?? "").trim()
  const contractName = String(params.contract.name ?? "").trim() || null
  const contractMaturityId =
    params.contract.contractMaturityId != null
      ? String(params.contract.contractMaturityId)
      : null
  const productId =
    params.maturity?.productId != null ? String(params.maturity.productId) : null
  const productName = params.product?.name?.trim() || null
  const valuePerPoint = finitePositive(params.product?.valuePerPoint)
  const tickSize = finitePositive(params.product?.tickSize)

  let metadataQuality: TradovateMetadataQuality = "UNRESOLVED"
  let resolutionStage = "contract"
  let unresolvedReason: string | null = null

  const symbolRoot = symbolRootFromNames(productName, contractName)

  if (params.product && productName && symbolRoot) {
    metadataQuality = "RESOLVED_PRODUCT"
    resolutionStage = "product"
  } else if (symbolRoot && contractName) {
    metadataQuality = "RESOLVED_CONTRACT"
    resolutionStage = "contract_name"
  } else if (!params.maturity && contractMaturityId) {
    unresolvedReason = "maturity_missing"
    resolutionStage = "contract_maturity"
  } else if (params.maturity && !params.product && productId) {
    unresolvedReason = "product_missing"
    resolutionStage = "product"
  } else {
    unresolvedReason = "symbol_root_unresolved"
    resolutionStage = "unresolved"
  }

  return {
    contractId,
    contractName,
    contractMaturityId,
    productId,
    productName,
    symbolRoot,
    valuePerPoint,
    tickSize,
    metadataQuality,
    resolutionStage,
    unresolvedReason,
  }
}

export function unresolvedTradovateContractSnapshot(
  contractId: string
): TradovateContractMetadataSnapshot {
  return {
    contractId: String(contractId).trim(),
    contractName: null,
    contractMaturityId: null,
    productId: null,
    productName: null,
    symbolRoot: null,
    valuePerPoint: null,
    tickSize: null,
    metadataQuality: "UNRESOLVED",
    resolutionStage: "unresolved",
    unresolvedReason: "not_fetched",
  }
}

export function snapshotToResolvedTradovateContract(
  snapshot: TradovateContractMetadataSnapshot
): ResolvedTradovateContractSnapshot {
  return {
    contractId: snapshot.contractId,
    contractName: snapshot.contractName ?? "",
    symbolRoot: snapshot.symbolRoot ?? "",
    valuePerPoint: snapshot.valuePerPoint,
  }
}

export function executionHintToMetadataSnapshot(
  hint: TradovateExecutionContractHint
): TradovateContractMetadataSnapshot | null {
  const contractId = String(hint.external_contract_id ?? "").trim()
  if (!contractId) return null

  const root = String(hint.symbol_root ?? "").trim()
  const name = String(hint.contract_name ?? "").trim()
  const symbolRoot =
    isValidResolvedTradovateSymbol(root)
      ? normalizeFuturesSymbol(root) || root
      : symbolRootFromNames(null, name)

  if (!symbolRoot && !name && !finitePositive(hint.value_per_point)) return null

  return {
    contractId,
    contractName: name || null,
    contractMaturityId: null,
    productId: null,
    productName: null,
    symbolRoot,
    valuePerPoint: finitePositive(hint.value_per_point),
    tickSize: finitePositive(hint.tick_size),
    metadataQuality: hint.metadata_quality ?? "PERSISTED_VALID_HINT",
    resolutionStage: "execution_ledger",
    unresolvedReason: symbolRoot ? null : "hint_partial",
  }
}

export function mergeTradovateContractMetadataSnapshots(
  existing: TradovateContractMetadataSnapshot | null | undefined,
  incoming: TradovateContractMetadataSnapshot | null | undefined
): TradovateContractMetadataSnapshot {
  const base =
    existing ??
    incoming ??
    unresolvedTradovateContractSnapshot("")
  const other = existing && incoming ? incoming : null
  if (!other || other.contractId !== base.contractId) {
    return base.contractId ? base : unresolvedTradovateContractSnapshot(other?.contractId ?? "")
  }

  const existingRank = metadataQualityRank(base.metadataQuality)
  const incomingRank = metadataQualityRank(other.metadataQuality)
  const preferIncoming = incomingRank > existingRank
  const primary = preferIncoming ? other : base
  const secondary = preferIncoming ? base : other

  const symbolRoot =
    (isValidResolvedTradovateSymbol(primary.symbolRoot)
      ? primary.symbolRoot
      : null) ??
    (isValidResolvedTradovateSymbol(secondary.symbolRoot)
      ? secondary.symbolRoot
      : null)

  const valuePerPoint = primary.valuePerPoint ?? secondary.valuePerPoint
  const tickSize = primary.tickSize ?? secondary.tickSize

  const metadataQuality =
    metadataQualityRank(primary.metadataQuality) >= metadataQualityRank(secondary.metadataQuality)
      ? primary.metadataQuality
      : secondary.metadataQuality

  return {
    contractId: primary.contractId,
    contractName: primary.contractName ?? secondary.contractName,
    contractMaturityId: primary.contractMaturityId ?? secondary.contractMaturityId,
    productId: primary.productId ?? secondary.productId,
    productName: primary.productName ?? secondary.productName,
    symbolRoot,
    valuePerPoint,
    tickSize,
    metadataQuality:
      symbolRoot && metadataQuality === "UNRESOLVED" ? "PERSISTED_VALID_HINT" : metadataQuality,
    resolutionStage: primary.resolutionStage,
    unresolvedReason: symbolRoot ? null : primary.unresolvedReason ?? secondary.unresolvedReason,
  }
}

export function logTradovateContractResolutionSummary(
  stats: TradovateContractResolutionStats
): void {
  console.info(
    [
      "[TradovateContractResolution]",
      `contractIds=${stats.contractIds}`,
      `contractResolved=${stats.contractResolved}`,
      `maturityResolved=${stats.maturityResolved}`,
      `productResolved=${stats.productResolved}`,
      `productVppResolved=${stats.productVppResolved}`,
      `persistedHintUsed=${stats.persistedHintUsed}`,
      `localFallbackUsed=${stats.localFallbackUsed}`,
      `unresolved=${stats.unresolved}`,
      `numericTickerPrevented=${stats.numericTickerPrevented}`,
    ].join(" ")
  )
}

export function brokerContractMetaFromSnapshot(
  snapshot: TradovateContractMetadataSnapshot
): BrokerContractMeta {
  const root =
    snapshot.symbolRoot && isValidResolvedTradovateSymbol(snapshot.symbolRoot)
      ? snapshot.symbolRoot
      : ""
  return {
    symbolRoot: root,
    contractName: snapshot.contractName,
    valuePerPoint: snapshot.valuePerPoint,
    tickSize: snapshot.tickSize,
    metadataQuality: snapshot.metadataQuality,
  }
}

export function logTradovateContractUnresolved(
  snapshot: TradovateContractMetadataSnapshot
): void {
  console.info(
    [
      "[TradovateContractResolution]",
      "unresolvedContract",
      `contractId=${snapshot.contractId}`,
      `contractName=${snapshot.contractName ?? "null"}`,
      `productName=${snapshot.productName ?? "null"}`,
      `resolutionStage=${snapshot.resolutionStage}`,
      `reason=${snapshot.unresolvedReason ?? "unknown"}`,
    ].join(" ")
  )
}

/** Used when product/items fetch fails but contract name still resolves a root. */
export function downgradeSnapshotAfterProductFetchFailure(
  snapshot: TradovateContractMetadataSnapshot
): TradovateContractMetadataSnapshot {
  if (snapshot.metadataQuality !== "RESOLVED_PRODUCT") return snapshot
  return {
    ...snapshot,
    metadataQuality: symbolRootFromNames(null, snapshot.contractName)
      ? "RESOLVED_CONTRACT"
      : "UNRESOLVED",
    unresolvedReason: "product_fetch_failed",
    valuePerPoint: null,
  }
}

export function downgradeSnapshotAfterMaturityFetchFailure(
  snapshot: TradovateContractMetadataSnapshot
): TradovateContractMetadataSnapshot {
  if (snapshot.metadataQuality === "UNRESOLVED") return snapshot
  return {
    ...snapshot,
    metadataQuality: "UNRESOLVED",
    unresolvedReason: "maturity_fetch_failed",
    resolutionStage: "contract_maturity",
  }
}

export { symbolRootFromNames as tradovateSymbolRootFromNamesForTests }
