/**
 * Session-scoped cache when rpc_v1_getting_started_signals is not deployed.
 */

import { BackendV2RpcError } from "./backendV2/rpcClient.ts"

const SESSION_KEY = "tt.getting_started.rpc_unavailable"

export function isGettingStartedRpcCachedUnavailable(): boolean {
  if (typeof sessionStorage === "undefined") return false
  try {
    return sessionStorage.getItem(SESSION_KEY) === "1"
  } catch {
    return false
  }
}

export function markGettingStartedRpcUnavailable(): void {
  if (typeof sessionStorage === "undefined") return
  try {
    sessionStorage.setItem(SESSION_KEY, "1")
  } catch {
    /* ignore */
  }
}

export function clearGettingStartedRpcUnavailableCache(): void {
  if (typeof sessionStorage === "undefined") return
  try {
    sessionStorage.removeItem(SESSION_KEY)
  } catch {
    /* ignore */
  }
}

/** @internal */
export function resetGettingStartedRpcAvailabilityForTests(): void {
  clearGettingStartedRpcUnavailableCache()
}

export function isGettingStartedRpcUnavailable(error: unknown): boolean {
  if (!(error instanceof BackendV2RpcError)) return false
  const msg = (error.message ?? "").toLowerCase()
  const code = (error.code ?? "").toLowerCase()
  return (
    code === "pgrst202" ||
    code === "42883" ||
    (msg.includes("404") &&
      msg.includes("rpc_v1_getting_started_signals")) ||
    msg.includes("could not find the function") ||
    msg.includes("rpc_v1_getting_started_signals")
  )
}
