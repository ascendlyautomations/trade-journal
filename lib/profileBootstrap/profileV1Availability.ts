/**
 * Session-scoped cache when rpc_v1_profile_bootstrap is not deployed.
 */

const SESSION_KEY = "tt.profile.v1_unavailable"

export function isProfileBootstrapRpcCachedUnavailable(): boolean {
  if (typeof sessionStorage === "undefined") return false
  try {
    return sessionStorage.getItem(SESSION_KEY) === "1"
  } catch {
    return false
  }
}

export function markProfileBootstrapRpcUnavailable(): void {
  if (typeof sessionStorage === "undefined") return
  try {
    sessionStorage.setItem(SESSION_KEY, "1")
  } catch {
    /* ignore */
  }
}

export function clearProfileBootstrapRpcUnavailableCache(): void {
  if (typeof sessionStorage === "undefined") return
  try {
    sessionStorage.removeItem(SESSION_KEY)
  } catch {
    /* ignore */
  }
}

/** @internal */
export function resetProfileBootstrapRpcAvailabilityForTests(): void {
  clearProfileBootstrapRpcUnavailableCache()
}
