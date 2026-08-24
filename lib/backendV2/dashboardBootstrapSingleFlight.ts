/**
 * Process-wide Dashboard Bootstrap single-flight (Symbol.for).
 * Reserve Promise BEFORE network — same lesson as Session Phase 2.6.
 */

type FlightSlot<T> = {
  promise: Promise<T>
  settledOk: boolean
}

const FLIGHT_SYMBOL = Symbol.for("tradetraxs.dashboardBootstrap.flights")

type FlightStore = {
  byUserId: Map<string, FlightSlot<unknown>>
}

function store(): FlightStore {
  const g = globalThis as typeof globalThis & {
    [FLIGHT_SYMBOL]?: FlightStore
  }
  if (!g[FLIGHT_SYMBOL]) {
    g[FLIGHT_SYMBOL] = { byUserId: new Map() }
  }
  return g[FLIGHT_SYMBOL]
}

export function getDashboardBootstrapFlight<T>(
  userId: string
): Promise<T> | null {
  return (store().byUserId.get(userId)?.promise as Promise<T> | undefined) ?? null
}

export function beginDashboardBootstrapFlight<T>(
  userId: string,
  start: () => Promise<T>
): Promise<T> {
  const existing = store().byUserId.get(userId)
  if (existing) return existing.promise as Promise<T>

  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((res, rej) => {
    resolve = res
    reject = rej
  })
  const slot: FlightSlot<T> = { promise, settledOk: false }
  store().byUserId.set(userId, slot as FlightSlot<unknown>)

  start().then(
    (result) => {
      slot.settledOk = true
      resolve(result)
    },
    (err) => {
      if (store().byUserId.get(userId) === slot) {
        store().byUserId.delete(userId)
      }
      reject(err)
    }
  )
  return promise
}

export function clearDashboardBootstrapFlights(userId?: string | null): void {
  if (userId) {
    store().byUserId.delete(userId)
    return
  }
  store().byUserId.clear()
}

export function __resetDashboardBootstrapFlightsForTests(): void {
  store().byUserId.clear()
}
