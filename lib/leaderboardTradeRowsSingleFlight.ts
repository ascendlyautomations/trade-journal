/**
 * Process-wide single-flight for leaderboard trade row scans (SSR / API).
 */

import type { TradeForLeaderboard } from "./leaderboardChart.ts"

const FLIGHT_SYMBOL = Symbol.for("tradetraxs.leaderboardTradeRows.flight")

type FlightStore = {
  byKey: Map<string, Promise<TradeForLeaderboard[]>>
}

function store(): FlightStore {
  const g = globalThis as typeof globalThis & {
    [FLIGHT_SYMBOL]?: FlightStore
  }
  if (!g[FLIGHT_SYMBOL]) g[FLIGHT_SYMBOL] = { byKey: new Map() }
  return g[FLIGHT_SYMBOL]
}

export function leaderboardTradeRowsFlightKey(maxRows: number): string {
  return `maxRows:${Math.max(1, Math.min(maxRows, 3000))}`
}

export function withLeaderboardTradeRowsSingleFlight<T>(
  key: string,
  start: () => Promise<T>
): Promise<T> {
  const s = store()
  const existing = s.byKey.get(key)
  if (existing) return existing as Promise<T>

  const promise = start().finally(() => {
    if (s.byKey.get(key) === promise) {
      s.byKey.delete(key)
    }
  })
  s.byKey.set(key, promise as Promise<TradeForLeaderboard[]>)
  return promise
}

/** @internal */
export function __resetLeaderboardTradeRowsFlightsForTests(): void {
  store().byKey.clear()
}
