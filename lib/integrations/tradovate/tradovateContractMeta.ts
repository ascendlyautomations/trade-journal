import { normalizeFuturesSymbol } from "../../normalizeFuturesSymbol.ts"
import type { ResolvedTradovateContract } from "./tradovateMarketDataClient.ts"
import {
  metadataQualityRank,
  type TradovateMetadataQuality,
} from "./tradovateMetadataQuality.ts"

export type BrokerContractMeta = {
  symbolRoot: string
  contractName?: string | null
  executionSymbolRoot?: string | null
  executionContractName?: string | null
  valuePerPoint?: number | null
  tickSize?: number | null
  metadataQuality?: TradovateMetadataQuality
}

export type TradovateExecutionContractHint = {
  external_contract_id: string
  symbol_root?: string | null
  contract_name?: string | null
  value_per_point?: number | null
  tick_size?: number | null
  metadata_quality?: TradovateMetadataQuality | null
}

export function isNumericTradovateContractKey(value: string): boolean {
  return /^\d+$/.test(value.trim())
}

/** Human-readable futures root/ticker — never a Tradovate numeric contract id. */
export function isValidResolvedTradovateSymbol(
  value: string | null | undefined
): boolean {
  const t = String(value ?? "").trim()
  if (!t) return false
  if (isNumericTradovateContractKey(t)) return false
  const normalized = normalizeFuturesSymbol(t)
  return Boolean(normalized && !isNumericTradovateContractKey(normalized))
}

export function isAuthoritativeFuturesTicker(
  ticker: string | null | undefined
): boolean {
  return isValidResolvedTradovateSymbol(ticker)
}

function sanitizeSymbolRoot(value: string | null | undefined): string | null {
  const t = String(value ?? "").trim()
  if (!t || isNumericTradovateContractKey(t)) return null
  const normalized = normalizeFuturesSymbol(t)
  if (normalized && isValidResolvedTradovateSymbol(normalized)) return normalized
  if (isValidResolvedTradovateSymbol(t)) return t
  return null
}

/** Best-effort symbol hint from a persisted execution row (matches repair SQL). */
export function tradovateExecutionSymbolHint(params: {
  symbol_root?: string | null
  contract_name?: string | null
}): string | null {
  const root = sanitizeSymbolRoot(params.symbol_root)
  if (root) return root
  const name = String(params.contract_name ?? "").trim()
  if (!name) return null
  return sanitizeSymbolRoot(normalizeFuturesSymbol(name) || name)
}

function finitePositive(n: unknown): number | null {
  if (n == null) return null
  const v = Number(n)
  return Number.isFinite(v) && v > 0 ? v : null
}

export type TradovateExecutionMetadataMergeResult = {
  symbol_root: string | null
  contract_name: string | null
  value_per_point: number | null
  tick_size: number | null
  metadata_quality: TradovateMetadataQuality
  numericTickerPrevented: boolean
}

/** Never downgrade execution ledger contract fields during REST enrichment. */
export function mergeTradovateExecutionContractFields(
  existing: { symbol_root?: string | null; contract_name?: string | null },
  incoming: { symbol_root: string; contract_name: string }
): { symbol_root: string | null; contract_name: string | null } {
  const merged = mergeTradovateExecutionMetadataFields(
    {
      symbol_root: existing.symbol_root,
      contract_name: existing.contract_name,
    },
    {
      symbol_root: incoming.symbol_root,
      contract_name: incoming.contract_name,
      metadata_quality: "RESOLVED_CONTRACT",
    }
  )
  return {
    symbol_root: merged.symbol_root,
    contract_name: merged.contract_name,
  }
}

export function mergeTradovateExecutionMetadataFields(
  existing: {
    symbol_root?: string | null
    contract_name?: string | null
    value_per_point?: number | null
    tick_size?: number | null
    metadata_quality?: TradovateMetadataQuality | null
  },
  incoming: {
    symbol_root?: string | null
    contract_name?: string | null
    value_per_point?: number | null
    tick_size?: number | null
    metadata_quality?: TradovateMetadataQuality | null
  }
): TradovateExecutionMetadataMergeResult {
  let numericTickerPrevented = false

  const existingRoot = sanitizeSymbolRoot(existing.symbol_root)
  const incomingRoot = sanitizeSymbolRoot(incoming.symbol_root)
  if (
    String(incoming.symbol_root ?? "").trim() &&
    !incomingRoot &&
    (existingRoot || isNumericTradovateContractKey(String(incoming.symbol_root)))
  ) {
    numericTickerPrevented = true
  }

  const existingRank = metadataQualityRank(
    existing.metadata_quality ?? (existingRoot ? "PERSISTED_VALID_HINT" : "UNRESOLVED")
  )
  const incomingRank = metadataQualityRank(
    incoming.metadata_quality ?? (incomingRoot ? "RESOLVED_CONTRACT" : "UNRESOLVED")
  )

  let symbol_root: string | null = null
  if (existingRoot && incomingRoot) {
    symbol_root = incomingRank > existingRank ? incomingRoot : existingRoot
  } else {
    symbol_root = existingRoot ?? incomingRoot
  }

  const contract_name =
    String(existing.contract_name ?? "").trim() ||
    String(incoming.contract_name ?? "").trim() ||
    null

  const existingVpp = finitePositive(existing.value_per_point)
  const incomingVpp = finitePositive(incoming.value_per_point)
  let value_per_point: number | null = null
  if (existingVpp != null && incomingVpp != null) {
    value_per_point = incomingRank >= existingRank ? incomingVpp : existingVpp
  } else {
    value_per_point = existingVpp ?? incomingVpp
  }

  const existingTick = finitePositive(existing.tick_size)
  const incomingTick = finitePositive(incoming.tick_size)
  const tick_size = existingTick ?? incomingTick

  let metadata_quality: TradovateMetadataQuality = "UNRESOLVED"
  if (symbol_root) {
    const rank = Math.max(
      existingRank,
      incomingRank,
      symbol_root ? 2 : 0
    )
    if (rank >= metadataQualityRank("RESOLVED_PRODUCT")) metadata_quality = "RESOLVED_PRODUCT"
    else if (rank >= metadataQualityRank("RESOLVED_CONTRACT"))
      metadata_quality = "RESOLVED_CONTRACT"
    else if (rank >= metadataQualityRank("PERSISTED_VALID_HINT"))
      metadata_quality = "PERSISTED_VALID_HINT"
    else metadata_quality = "UNRESOLVED"
  }

  if (!symbol_root && !contract_name) {
    metadata_quality = "UNRESOLVED"
  }

  return {
    symbol_root,
    contract_name,
    value_per_point,
    tick_size,
    metadata_quality,
    numericTickerPrevented,
  }
}

function executionHintScore(row: TradovateExecutionContractHint): number {
  const rootHint = tradovateExecutionSymbolHint(row)
  if (rootHint) return 2
  if (String(row.contract_name ?? "").trim()) return 1
  if (String(row.symbol_root ?? "").trim()) return 0
  return -1
}

/** One hint per contract id — prefer rows that resolve to a futures root. */
export function aggregateTradovateExecutionContractHints(
  executionHints: TradovateExecutionContractHint[]
): TradovateExecutionContractHint[] {
  const byContract = new Map<string, TradovateExecutionContractHint>()
  for (const row of executionHints) {
    const key = String(row.external_contract_id ?? "").trim()
    if (!key) continue
    const prev = byContract.get(key)
    if (!prev || executionHintScore(row) > executionHintScore(prev)) {
      byContract.set(key, row)
    }
  }
  return [...byContract.values()]
}

/** Canonical futures root from merged REST + execution metadata. */
export function normalizedFuturesRootFromContractMeta(
  meta?: BrokerContractMeta | null
): string | null {
  if (!meta) return null
  for (const raw of [meta.symbolRoot, meta.executionSymbolRoot, meta.contractName]) {
    const resolved = sanitizeSymbolRoot(raw)
    if (resolved) return resolved
  }
  return null
}

/** Final trades.ticker — never a numeric Tradovate contract id. */
export function resolveBrokerTradeTicker(params: {
  contract?: BrokerContractMeta | null
  contractId: string
}): string {
  const fromMeta = normalizedFuturesRootFromContractMeta(params.contract)
  if (fromMeta) return fromMeta
  return ""
}

/**
 * Merge Tradovate REST contract resolution with execution-row hints.
 * Execution hints survive when /v1/contract/items fails or returns partial data.
 */
export function mergeTradovateContractMetaMaps(
  resolved: Map<string, ResolvedTradovateContract>,
  executionHints: TradovateExecutionContractHint[]
): Map<string, BrokerContractMeta> {
  const out = new Map<string, BrokerContractMeta>()

  for (const [contractId, meta] of resolved) {
    const key = String(contractId).trim()
    const root = sanitizeSymbolRoot(meta.symbolRoot) ?? ""
    out.set(key, {
      symbolRoot: root,
      contractName: meta.contractName || null,
      valuePerPoint: meta.valuePerPoint,
      metadataQuality: root ? "RESOLVED_PRODUCT" : "UNRESOLVED",
    })
  }

  const aggregatedHints = aggregateTradovateExecutionContractHints(executionHints)
  for (const row of aggregatedHints) {
    const key = String(row.external_contract_id ?? "").trim()
    if (!key) continue
    const existing = out.get(key)
    const hintRoot = sanitizeSymbolRoot(row.symbol_root)
    const hintName = String(row.contract_name ?? "").trim() || null
    const mergedFields = mergeTradovateExecutionMetadataFields(
      {
        symbol_root: existing?.symbolRoot,
        contract_name: existing?.contractName,
        value_per_point: existing?.valuePerPoint,
        tick_size: existing?.tickSize,
        metadata_quality: existing?.metadataQuality,
      },
      {
        symbol_root: hintRoot,
        contract_name: hintName,
        value_per_point: row.value_per_point,
        tick_size: row.tick_size,
        metadata_quality: row.metadata_quality ?? "PERSISTED_VALID_HINT",
      }
    )
    out.set(key, {
      symbolRoot: mergedFields.symbol_root ?? "",
      contractName: mergedFields.contract_name,
      executionSymbolRoot: hintRoot,
      executionContractName: hintName,
      valuePerPoint: mergedFields.value_per_point,
      tickSize: mergedFields.tick_size,
      metadataQuality: mergedFields.metadata_quality,
    })
  }

  return out
}
