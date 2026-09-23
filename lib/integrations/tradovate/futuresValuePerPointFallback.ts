import { normalizeFuturesSymbol } from "../../normalizeFuturesSymbol.ts"

/**
 * When Tradovate product metadata omits valuePerPoint, derive a best-effort
 * multiplier from the normalized root symbol so closed trades still get gross P&L.
 * Fees may still be zero when fee enrichment fails; missing fees must not block gross.
 */
const ROOT_VALUE_PER_POINT: Readonly<Record<string, number>> = {
  ES: 50,
  MES: 5,
  NQ: 20,
  MNQ: 2,
  YM: 5,
  MYM: 0.5,
  RTY: 50,
  M2K: 5,
  CL: 1000,
  MCL: 100,
  GC: 100,
  MGC: 10,
  SI: 5000,
  SIL: 1000,
  NG: 10000,
  ZB: 1000,
  ZN: 1000,
  ZF: 1000,
  ZT: 2000,
  UB: 1000,
  HO: 42000,
  RB: 42000,
  BTC: 5,
  MBT: 0.1,
  ETH: 50,
  MET: 0.1,
}

export function fallbackFuturesValuePerPoint(
  symbolRoot: string | null | undefined
): number | null {
  const root = normalizeFuturesSymbol(symbolRoot ?? "")
  if (!root) return null
  const direct = ROOT_VALUE_PER_POINT[root]
  if (direct != null && direct > 0) return direct
  return null
}

export function resolveEffectiveValuePerPoint(params: {
  symbolRoot: string
  contractValuePerPoint?: number | null
}): number | null {
  const fromContract = params.contractValuePerPoint
  if (fromContract != null && Number.isFinite(fromContract) && fromContract > 0) {
    return fromContract
  }
  return fallbackFuturesValuePerPoint(params.symbolRoot)
}
