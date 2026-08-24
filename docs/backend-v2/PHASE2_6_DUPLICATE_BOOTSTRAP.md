# Backend V2 Phase 2.6b — Same-timestamp duplicate Session RPC

## What the HAR proved

Two `rpc_v1_session_bootstrap` requests with the **same start timestamp**
(one ~26ms, one ~3.8s) means two `fetch`/`client.rpc` calls were scheduled in the
**same synchronous turn** (or before either single-flight map insert completed) —
not a later `SIGNED_IN` follow-up.

## Exact bug

In `beginSessionBootstrapFlight` the previous order was:

```ts
const promise = start()  // ← starts supabase.rpc / fetch HERE
store.set(userId, slot)  // ← map insert AFTER
```

Any second caller that entered before `store.set` (reentrant `start()`, duplicate
module evaluation racing, or two auth applies that both passed the outer
`getSessionBootstrapFlight` miss) could call `start()` again → **two network RPCs
at the same instant**.

## Checklist answers

| Question | Answer |
|----------|--------|
| 1. Two copies of singleFlight module? | Possible under Turbopack; mitigated with `Symbol.for` shared store + module-eval counter |
| 2. Two providers / repos? | Only `UserProfileProvider` calls `loadSessionBootstrapForUser`. Repos are ephemeral; not the network owner |
| 3. globalThis shared? | Yes via `Symbol.for("tradetraxs.sessionBootstrap.*")` (cross-instance) |
| 4. Promise inserted before await RPC? | **Now yes** — flight reserved before `start()`; RPC gate reserved before `client.rpc` |
| 5. Direct `supabase.rpc` bypass? | Only path is `SessionRpcBootstrapRepository` → transport; transport now gates session RPC |

## Fix layers

1. **Flight:** reserve Promise in `Symbol.for` map **before** `start()`
2. **Network gate:** `ensureSupabaseSessionRpcSingleFlight` patches shared `supabase.rpc` so session bootstrap goes through `runSessionBootstrapRpcOnce` (Promise reserved **before** `originalRpc`)
3. **Invalidate:** logout clears cache + flights + RPC gate
4. **Dev logs:** `flight CREATE` / `flight REUSE` / `RPC gate NETWORK start` / `RPC gate REUSE` with stacks

Hard-refresh after restarting `npm run dev` so stale HMR bundles are discarded.
