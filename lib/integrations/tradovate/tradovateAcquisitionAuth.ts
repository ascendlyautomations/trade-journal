/** Auth-related Tradovate acquisition failures (not zero-trade success). */
export function tradovateAcquisitionErrorsIndicateAuthFailure(
  acquisitionErrors: string[]
): boolean {
  for (const raw of acquisitionErrors) {
    const e = raw.toLowerCase()
    if (e.includes("reconnect_required")) return true
    if (e.includes(":unauthorized") || e.endsWith(":unauthorized")) return true
    if (e.includes("order_deps:unauthorized")) return true
    if (e.includes("fill_list:unauthorized")) return true
    if (e.includes("position_deps:unauthorized")) return true
    if (e.includes("not_connected")) return true
  }
  return false
}
