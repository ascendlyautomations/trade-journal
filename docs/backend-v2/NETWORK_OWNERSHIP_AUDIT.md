# Backend V2 — Network ownership (Session)

Temporary `[PROOF]` / `supabaseNetworkProof` instrumentation has been **removed**.

## Ownership (production)

| Concern | Owner |
|---------|--------|
| Session bootstrap RPC | `loadSessionBootstrapForUser` → `SessionRpcBootstrapRepository` → `BackendV2RpcClient` |
| Duplicate prevention | Process-wide single-flight (`sessionBootstrapSingleFlight`) + RPC gate (`sessionBootstrapRpcGate`) + optional `ensureSupabaseSessionRpcSingleFlight` on the shared client |
| Browser Supabase clients | Plain `createClient` in `lib/supabaseClient.ts` and `lib/supabase.ts` (no fetch monkey-patch) |

## Historical note

An earlier audit used `window.__TT_SUPABASE_PROOF__` and `[PROOF]` `console.error` logs to attribute duplicate `rpc_v1_session_bootstrap` HTTP calls. That tooling is gone; behavior is unchanged aside from quieter consoles / no Next.js error overlays from proof logs.
