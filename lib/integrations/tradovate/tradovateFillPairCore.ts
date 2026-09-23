import type { BrokerContractMeta } from "./tradovateContractMeta.ts"
import { normalizedFuturesRootFromContractMeta } from "./tradovateContractMeta.ts"
import { resolveEffectiveValuePerPoint } from "./futuresValuePerPointFallback.ts"
import type { NormalizedTradovateFillPair } from "./tradovateFillPairModels.ts"
import { dedupeTradovateFillPairsById } from "./tradovateFillPairModels.ts"

export type TradovateLedgerFillContext = {
  fillId: string
  contractId: string
  tradeDate: string
}

/** Tradovate FillPair gross: (sellPrice − buyPrice) × qty × authoritative valuePerPoint. */
export function computeTradovateFillPairGrossPnl(params: {
  pair: NormalizedTradovateFillPair
  contract?: BrokerContractMeta | null
  contractId: string
}): { grossPnl: number | null; unresolvedMetadata: boolean } {
  const root = normalizedFuturesRootFromContractMeta(params.contract)
  const vpp = resolveEffectiveValuePerPoint({
    symbolRoot: root ?? "",
    contractValuePerPoint: params.contract?.valuePerPoint ?? null,
  })
  if (vpp == null || vpp <= 0 || !root) {
    return { grossPnl: null, unresolvedMetadata: true }
  }
  const points = params.pair.sellPrice - params.pair.buyPrice
  const grossPnl = points * params.pair.qty * vpp
  return { grossPnl, unresolvedMetadata: false }
}

export function mergeAccountScopedTradovateFillPairs(params: {
  primaryFromLdeps: NormalizedTradovateFillPair[]
  supplementalFromList: NormalizedTradovateFillPair[]
}): NormalizedTradovateFillPair[] {
  const merged = dedupeTradovateFillPairsById(params.primaryFromLdeps)
  const seen = new Set(merged.map((p) => p.id))
  for (const pair of dedupeTradovateFillPairsById(params.supplementalFromList)) {
    if (seen.has(pair.id)) continue
    seen.add(pair.id)
    merged.push(pair)
  }
  return merged
}

export function completedTradovateFillPairs(
  pairs: NormalizedTradovateFillPair[]
): NormalizedTradovateFillPair[] {
  return pairs.filter((p) => p.active !== false)
}

export function contractIdForFillPair(
  pair: NormalizedTradovateFillPair,
  fillsById: Map<string, TradovateLedgerFillContext>
): string | null {
  const buy = fillsById.get(pair.buyFillId)
  const sell = fillsById.get(pair.sellFillId)
  const contractId = buy?.contractId ?? sell?.contractId
  return contractId ? String(contractId) : null
}

export function tradeDateForFillPair(
  pair: NormalizedTradovateFillPair,
  fillsById: Map<string, TradovateLedgerFillContext>
): string | null {
  const sell = fillsById.get(pair.sellFillId)
  const buy = fillsById.get(pair.buyFillId)
  return sell?.tradeDate ?? buy?.tradeDate ?? null
}
