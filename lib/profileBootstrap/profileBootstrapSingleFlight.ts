/**
 * Process-wide Profile bootstrap single-flight (Symbol.for).
 */

type FlightSlot<T> = {
  promise: Promise<T>
  viewerKey: string
  identifier: string
}

const FLIGHT_SYMBOL = Symbol.for("tradetraxs.profileBootstrap.flights")

type FlightStore = {
  byKey: Map<string, FlightSlot<unknown>>
}

function store(): FlightStore {
  const g = globalThis as typeof globalThis & {
    [FLIGHT_SYMBOL]?: FlightStore
  }
  if (!g[FLIGHT_SYMBOL]) g[FLIGHT_SYMBOL] = { byKey: new Map() }
  return g[FLIGHT_SYMBOL]
}

export function profileBootstrapFlightKey(
  viewerKey: string,
  identifier: string
): string {
  return `${viewerKey}|${identifier.trim().toLowerCase()}`
}

export function getProfileBootstrapFlight<T>(
  key: string
): Promise<T> | null {
  return (store().byKey.get(key)?.promise as Promise<T> | undefined) ?? null
}

export function beginProfileBootstrapFlight<T>(
  key: string,
  viewerKey: string,
  identifier: string,
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
  const slot: FlightSlot<T> = { promise, viewerKey, identifier }
  store().byKey.set(key, slot as FlightSlot<unknown>)

  start().then(
    (result) => resolve(result),
    (err) => {
      if (store().byKey.get(key) === slot) {
        store().byKey.delete(key)
      }
      reject(err)
    }
  )
  return promise
}

export function clearProfileBootstrapFlights(viewerKey?: string | null): void {
  if (viewerKey) {
    const s = store()
    for (const [k, slot] of s.byKey) {
      if (slot.viewerKey === viewerKey) s.byKey.delete(k)
    }
    return
  }
  store().byKey.clear()
}

/** @internal */
export function __resetProfileBootstrapFlightsForTests(): void {
  store().byKey.clear()
}
