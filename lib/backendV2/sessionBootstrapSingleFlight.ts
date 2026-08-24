/**
 * Process-wide Session Bootstrap single-flight.
 *
 * Uses Symbol.for + globalThis so duplicate Next.js/Turbopack module instances
 * still share one flight. The slot is reserved BEFORE start() runs so reentrant
 * or concurrent callers cannot start a second RPC.
 */

type FlightSlot<T> = {
  promise: Promise<T>
  settledOk: boolean
}

const FLIGHT_SYMBOL = Symbol.for("tradetraxs.sessionBootstrap.flights")

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

export function getSessionBootstrapFlight<T>(
  userId: string
): Promise<T> | null {
  const slot = store().byUserId.get(userId)
  return (slot?.promise as Promise<T> | undefined) ?? null
}

export function hasSessionBootstrapFlight(userId: string): boolean {
  return store().byUserId.has(userId)
}

/**
 * Register the flight promise for this user BEFORE invoking start().
 * Concurrent / reentrant callers share one Promise and never call start() twice.
 */
export function beginSessionBootstrapFlight<T>(
  userId: string,
  start: () => Promise<T>
): Promise<T> {
  const existing = store().byUserId.get(userId)
  if (existing) {
    return existing.promise as Promise<T>
  }

  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((res, rej) => {
    resolve = res
    reject = rej
  })

  const slot: FlightSlot<T> = { promise, settledOk: false }
  // CRITICAL: insert BEFORE start() so same-timestamp concurrent callers join.
  store().byUserId.set(userId, slot as FlightSlot<unknown>)

  start().then(
    (result) => {
      slot.settledOk = true
      resolve(result)
    },
    (err) => {
      const current = store().byUserId.get(userId)
      if (current === slot) {
        store().byUserId.delete(userId)
      }
      reject(err)
    }
  )

  return promise
}

/** Clear flights (logout / explicit invalidate). */
export function clearSessionBootstrapFlights(userId?: string | null): void {
  if (userId) {
    store().byUserId.delete(userId)
    return
  }
  store().byUserId.clear()
}

/** Test-only reset. */
export function __resetSessionBootstrapFlightsForTests(): void {
  store().byUserId.clear()
}
