/**
 * Session-scoped cache: skip slow V2 RPC probes when the function is not deployed.
 * Cleared on successful V2 call so a later migration apply is picked up in-session.
 */

const SESSION_KEY = "tt.messaging.v2_unavailable"

export function isMessagingV2CachedUnavailable(): boolean {
  if (typeof sessionStorage === "undefined") return false
  try {
    return sessionStorage.getItem(SESSION_KEY) === "1"
  } catch {
    return false
  }
}

export function markMessagingV2Unavailable(): void {
  if (typeof sessionStorage === "undefined") return
  try {
    sessionStorage.setItem(SESSION_KEY, "1")
  } catch {
    /* ignore quota / private mode */
  }
}

export function clearMessagingV2UnavailableCache(): void {
  if (typeof sessionStorage === "undefined") return
  try {
    sessionStorage.removeItem(SESSION_KEY)
  } catch {
    /* ignore */
  }
}

/** @internal */
export function resetMessagingV2AvailabilityForTests(): void {
  clearMessagingV2UnavailableCache()
}
