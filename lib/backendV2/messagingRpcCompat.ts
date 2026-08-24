/**
 * Messaging RPC version compatibility helpers (pure — safe for contract tests).
 */

import { BackendV2RpcError } from "./rpcClient.ts"

/** Strip composite cursor suffix for legacy V1 timestamptz pagination. */
export function v1CursorFromComposite(cursor: string): string {
  const pipe = cursor.indexOf("|")
  if (pipe === -1) return cursor
  return cursor.slice(0, pipe)
}

/** True when PostgREST/Postgres reports the V2 function is not deployed. */
export function isMessagingV2Unavailable(error: unknown): boolean {
  if (!(error instanceof BackendV2RpcError)) return false
  const msg = (error.message ?? "").toLowerCase()
  const code = (error.code ?? "").toLowerCase()
  return (
    code === "pgrst202" ||
    code === "42883" ||
    (msg.includes("404") && msg.includes("rpc_v2_messaging_bootstrap")) ||
    msg.includes("could not find the function") ||
    msg.includes("rpc_v2_messaging_bootstrap")
  )
}
