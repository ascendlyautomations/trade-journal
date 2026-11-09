/**
 * Deduplicate concurrent async work by key. One promise in flight per key;
 * concurrent callers await the same promise.
 */
export async function runSingleFlightByKey<T>(
  flights: Map<string, Promise<unknown>>,
  key: string,
  forceNewFlight: boolean,
  run: () => Promise<T>
): Promise<T> {
  const k = key.trim()
  if (forceNewFlight) {
    const prev = flights.get(k)
    if (prev) {
      await prev.catch(() => {})
    }
    flights.delete(k)
  } else {
    const existing = flights.get(k)
    if (existing) {
      return existing as Promise<T>
    }
  }

  const p = run().finally(() => {
    if (flights.get(k) === p) {
      flights.delete(k)
    }
  })
  flights.set(k, p)
  return p
}
