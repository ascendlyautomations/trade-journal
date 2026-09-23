import type { SupabaseClient } from "@supabase/supabase-js"
import type {
  TradovateContractMaturityRaw,
  TradovateContractRaw,
} from "./tradovateFillModels.ts"
import {
  fetchTradovateContractMaturitiesByIds,
  fetchTradovateContractsByIds,
  fetchTradovateProductsByIds,
  type ResolvedTradovateContract,
} from "./tradovateMarketDataClient.ts"
import {
  buildTradovateContractMetadataSnapshot,
  downgradeSnapshotAfterMaturityFetchFailure,
  downgradeSnapshotAfterProductFetchFailure,
  emptyTradovateContractResolutionStats,
  snapshotToResolvedTradovateContract,
  unresolvedTradovateContractSnapshot,
  type TradovateContractMetadataSnapshot,
  type TradovateContractResolutionStats,
} from "./tradovateContractResolutionCore.ts"

export {
  buildTradovateContractMetadataSnapshot,
  brokerContractMetaFromSnapshot,
  emptyTradovateContractResolutionStats,
  executionHintToMetadataSnapshot,
  logTradovateContractResolutionSummary,
  logTradovateContractUnresolved,
  mergeTradovateContractMetadataSnapshots,
  snapshotToResolvedTradovateContract,
  unresolvedTradovateContractSnapshot,
  type TradovateContractMetadataSnapshot,
  type TradovateContractResolutionStats,
  type TradovateMetadataQuality,
  metadataQualityRank,
} from "./tradovateContractResolutionCore.ts"

export async function resolveTradovateContractMetadataBatch(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  contractIds: string[]
): Promise<{
  cache: Map<string, TradovateContractMetadataSnapshot>
  stats: TradovateContractResolutionStats
}> {
  const unique = [...new Set(contractIds.filter(Boolean).map((id) => String(id).trim()))]
  const stats = emptyTradovateContractResolutionStats(unique.length)
  const cache = new Map<string, TradovateContractMetadataSnapshot>()

  if (unique.length === 0) return { cache, stats }

  let contracts: TradovateContractRaw[] = []
  let maturityFetchFailed = false
  let productFetchFailed = false

  try {
    contracts = await fetchTradovateContractsByIds(
      supabase,
      userId,
      connectionId,
      unique
    )
  } catch {
    for (const id of unique) {
      cache.set(id, unresolvedTradovateContractSnapshot(id))
    }
    stats.unresolved = unique.length
    return { cache, stats }
  }

  stats.contractResolved = contracts.length
  const contractById = new Map(contracts.map((c) => [String(c.id), c] as const))

  for (const id of unique) {
    if (!contractById.has(id)) {
      cache.set(id, {
        ...unresolvedTradovateContractSnapshot(id),
        unresolvedReason: "contract_not_in_response",
      })
      stats.unresolved += 1
    }
  }

  const maturityIds = [
    ...new Set(
      contracts
        .map((c) => (c.contractMaturityId != null ? String(c.contractMaturityId) : ""))
        .filter(Boolean)
    ),
  ]

  let maturities: TradovateContractMaturityRaw[] = []
  if (maturityIds.length > 0) {
    try {
      maturities = await fetchTradovateContractMaturitiesByIds(
        supabase,
        userId,
        connectionId,
        maturityIds
      )
      stats.maturityResolved = maturities.length
    } catch {
      maturityFetchFailed = true
    }
  }

  const productIds = [
    ...new Set(
      maturities
        .map((m) => (m.productId != null ? String(m.productId) : ""))
        .filter(Boolean)
    ),
  ]

  let products: Awaited<ReturnType<typeof fetchTradovateProductsByIds>> = []
  if (productIds.length > 0) {
    try {
      products = await fetchTradovateProductsByIds(
        supabase,
        userId,
        connectionId,
        productIds
      )
      stats.productResolved = products.length
    } catch {
      productFetchFailed = true
    }
  }

  const maturityById = new Map(maturities.map((m) => [String(m.id), m] as const))
  const productById = new Map(products.map((p) => [String(p.id), p] as const))

  for (const contract of contracts) {
    const contractId = String(contract.id)
    const maturity = maturityById.get(String(contract.contractMaturityId ?? ""))
    const product = maturity
      ? productById.get(String(maturity.productId ?? ""))
      : undefined

    let snapshot = buildTradovateContractMetadataSnapshot({
      contract,
      maturity: maturityFetchFailed ? null : maturity,
      product: productFetchFailed ? null : product,
    })

    if (maturityFetchFailed) {
      snapshot = downgradeSnapshotAfterMaturityFetchFailure(snapshot)
    } else if (productFetchFailed) {
      snapshot = downgradeSnapshotAfterProductFetchFailure(snapshot)
    }

    if (snapshot.valuePerPoint != null) stats.productVppResolved += 1
    if (snapshot.metadataQuality === "UNRESOLVED") stats.unresolved += 1

    cache.set(contractId, snapshot)
  }

  return { cache, stats }
}

export function resolvedSnapshotToMarketContract(
  snapshot: TradovateContractMetadataSnapshot
): ResolvedTradovateContract {
  const mapped = snapshotToResolvedTradovateContract(snapshot)
  return mapped
}
