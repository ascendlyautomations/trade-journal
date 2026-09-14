const refreshFlights = new Map<string, Promise<boolean>>()

/**
 * Coalesce concurrent Tradovate token refreshes for the same TradeTraxs user.
 * Returns true when refresh succeeded and credentials were persisted.
 */
export function runTradovateTokenRefreshSingleFlight(
  userId: string,
  refreshFn: () => Promise<boolean>
): Promise<boolean> {
  const key = `tradovate:${userId}`
  const existing = refreshFlights.get(key)
  if (existing) return existing

  const flight = refreshFn().finally(() => {
    refreshFlights.delete(key)
  })
  refreshFlights.set(key, flight)
  return flight
}
