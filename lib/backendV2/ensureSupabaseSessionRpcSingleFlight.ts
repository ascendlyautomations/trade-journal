/**
 * Patch the shared Supabase client so rpc_v1_session_bootstrap cannot double-fetch
 * even if an old HMR bundle bypasses BackendV2 transport single-flight.
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import { BackendV2RpcNames } from "./versioning.ts"
import { runSessionBootstrapRpcOnce } from "./sessionBootstrapRpcGate.ts"

const PATCHED = Symbol.for("tradetraxs.sessionBootstrap.supabaseClientPatched")

export function ensureSupabaseSessionRpcSingleFlight(
  client: SupabaseClient
): void {
  const c = client as SupabaseClient & {
    [PATCHED]?: boolean
    rpc: SupabaseClient["rpc"]
  }
  if (c[PATCHED]) return
  c[PATCHED] = true

  const originalRpc = c.rpc.bind(c) as (
    fn: string,
    args?: Record<string, unknown>,
    options?: Record<string, unknown>
  ) => PromiseLike<{ data: unknown; error: { message?: string; code?: string } | null }>

  c.rpc = ((fn: string, args?: Record<string, unknown>, options?: Record<string, unknown>) => {
    if (fn !== BackendV2RpcNames.session) {
      return originalRpc(fn, args, options)
    }
    return runSessionBootstrapRpcOnce(() =>
      Promise.resolve(originalRpc(fn, args, options))
    )
  }) as typeof c.rpc
}
