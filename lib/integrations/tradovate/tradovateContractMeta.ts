import { normalizeFuturesSymbol } from "../../normalizeFuturesSymbol.ts"
export type BrokerContractMeta = {
  symbolRoot: string
  contractName?: string | null
  executionSymbolRoot?: string | null
  executionContractName?: string | null
  valuePerPoint?: number | null
}
import type { ResolvedTradovateContract } from "./tradovateMarketDataClient.ts"

export type TradovateExecutionContractHint = {
  external_contract_id: string
  symbol_root?: string | null
  contract_name?: string | null
}

export function isNumericTradovateContractKey(value: string): boolean {
  return /^\d+$/.test(value.trim())
}

/** Best-effort symbol hint from a persisted execution row (matches repair SQL). */
export function tradovateExecutionSymbolHint(params: {
  symbol_root?: string | null
  contract_name?: string | null
}): string | null {
  const root = String(params.symbol_root ?? "").trim()
  if (root && !isNumericTradovateContractKey(root)) {
    return normalizeFuturesSymbol(root) || root
  }
  const name = String(params.contract_name ?? "").trim()
  if (!name) return null
  const fromName = normalizeFuturesSymbol(name)
  if (fromName && !isNumericTradovateContractKey(fromName)) return fromName
  return null
}

/** Never downgrade execution ledger contract fields during REST enrichment. */
export function mergeTradovateExecutionContractFields(
  existing: { symbol_root?: string | null; contract_name?: string | null },
  incoming: { symbol_root: string; contract_name: string }
): { symbol_root: string | null; contract_name: string | null } {
  const existingRoot = String(existing.symbol_root ?? "").trim()
  const existingName = String(existing.contract_name ?? "").trim()
  const incomingRoot = String(incoming.symbol_root ?? "").trim()
  const incomingName = String(incoming.contract_name ?? "").trim()

  const keepRoot =
    existingRoot && !isNumericTradovateContractKey(existingRoot)
      ? existingRoot
      : incomingRoot && !isNumericTradovateContractKey(incomingRoot)
        ? incomingRoot
        : existingRoot || incomingRoot || null

  const keepName =
    existingName ||
    incomingName ||
    null

  const normalizedFromName = keepName ? normalizeFuturesSymbol(keepName) : ""
  const symbol_root =
    keepRoot && !isNumericTradovateContractKey(keepRoot)
      ? keepRoot
      : normalizedFromName && !isNumericTradovateContractKey(normalizedFromName)
        ? normalizedFromName
        : keepRoot || null

  return {
    symbol_root: symbol_root || null,
    contract_name: keepName,
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
  // Priority: REST/merged symbol root → execution symbol_root → normalized contract_name
  for (const raw of [meta.symbolRoot, meta.executionSymbolRoot, meta.contractName]) {
    const trimmed = String(raw ?? "").trim()
    if (!trimmed) continue
    const normalized = normalizeFuturesSymbol(trimmed)
    if (normalized && !isNumericTradovateContractKey(normalized)) {
      return normalized
    }
    if (!isNumericTradovateContractKey(trimmed)) {
      return trimmed
    }
  }
  return null
}

/** Prefer human symbol roots over Tradovate numeric contract ids. */
export function resolveBrokerTradeTicker(params: {
  contract?: BrokerContractMeta | null
  contractId: string
}): string {
  const contractId = String(params.contractId).trim()
  const fromMeta = normalizedFuturesRootFromContractMeta(params.contract)
  if (fromMeta) return fromMeta
  return contractId
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
    out.set(key, {
      symbolRoot: meta.symbolRoot,
      contractName: meta.contractName,
      valuePerPoint: meta.valuePerPoint,
    })
  }

  const aggregatedHints = aggregateTradovateExecutionContractHints(executionHints)
  for (const row of aggregatedHints) {
    const key = String(row.external_contract_id ?? "").trim()
    if (!key) continue
    const existing = out.get(key)
    const hintRoot = row.symbol_root?.trim() || null
    const hintName = row.contract_name?.trim() || null
    const mergedRoot =
      existing?.symbolRoot && !isNumericTradovateContractKey(existing.symbolRoot)
        ? existing.symbolRoot
        : hintRoot && !isNumericTradovateContractKey(hintRoot)
          ? hintRoot
          : existing?.symbolRoot ?? hintRoot
    const mergedName = existing?.contractName ?? hintName
    const valuePerPoint = existing?.valuePerPoint ?? null
    const normalizedFromHints =
      normalizedFuturesRootFromContractMeta({
        symbolRoot: mergedRoot ?? "",
        contractName: mergedName,
        executionSymbolRoot: hintRoot,
        executionContractName: hintName,
      }) ?? undefined
    out.set(key, {
      symbolRoot: normalizedFromHints ?? mergedRoot ?? mergedName ?? key,
      contractName: mergedName,
      executionSymbolRoot: hintRoot,
      executionContractName: hintName,
      valuePerPoint,
    })
  }

  return out
}
