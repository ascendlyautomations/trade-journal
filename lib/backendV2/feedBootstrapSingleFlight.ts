/**
 * Process-wide Feed Bootstrap single-flight (Symbol.for).
 * Flight key includes scope/filter/cursor so concurrent modes do not collide.
 */

type FlightSlot<T> = {
  promise: Promise<T>
  settledOk: boolean
  userId: string
}

const FLIGHT_SYMBOL = Symbol.for("tradetraxs.feedBootstrap.flights")

type FlightStore = {
  byKey: Map<string, FlightSlot<unknown>>
}

function store(): FlightStore {
  const g = globalThis as typeof globalThis & {
    [FLIGHT_SYMBOL]?: FlightStore
  }
  if (!g[FLIGHT_SYMBOL]) {
    g[FLIGHT_SYMBOL] = { byKey: new Map() }
  }
  return g[FLIGHT_SYMBOL]
}

export function getFeedBootstrapFlight<T>(key: string): Promise<T> | null {
  return (store().byKey.get(key)?.promise as Promise<T> | undefined) ?? null
}

export function beginFeedBootstrapFlight<T>(
  key: string,
  userId: string,
  start: () => Promise<T>
): Promise<T> {
  const existing = store().byKey.get(key)
  if (existing) return existing.promise as Promise<T>

  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((res, rej) => {
    resolve = res
    reject = rej
  })
  const slot: FlightSlot<T> = { promise, settledOk: false, userId }
  store().byKey.set(key, slot as FlightSlot<unknown>)

  start().then(
    (result) => {
      slot.settledOk = true
      resolve(result)
    },
    (err) => {
      if (store().byKey.get(key) === slot) {
        store().byKey.delete(key)
      }
      reject(err)
    }
  )
  return promise
}

export function clearFeedBootstrapFlights(userId?: string | null): void {
  if (userId) {
    const s = store()
    for (const [k, slot] of s.byKey) {
      if (slot.userId === userId) s.byKey.delete(k)
    }
    return
  }
  store().byKey.clear()
}

export function __resetFeedBootstrapFlightsForTests(): void {
  store().byKey.clear()
}
