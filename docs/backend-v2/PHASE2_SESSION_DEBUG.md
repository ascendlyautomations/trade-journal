# Backend V2 Phase 2 Debug — Why RPC never appeared

## Root cause (confirmed in code)

1. **Flag gate in `UserProfileProvider`** only calls RPC when `resolveBackendV2Flag("session").enabled === true`.

2. **Env override was broken on the client**: Next.js does **not** inline dynamic `process.env[key]`. The previous resolver used a computed key, so in the browser `envRaw` was always `undefined` → source stayed **`default`** → **`enabled: false`** even with `NEXT_PUBLIC_BACKEND_V2_SESSION=1` in `.env.local`.

3. Therefore the **ELSE** branch always ran → `fetchSettingsProfileRow` → `/rest/v1/profiles`. **Zero** `rpc_v1_session_bootstrap` calls.

## Fix applied (wiring + instrumentation)

- `flags.ts`: static `process.env.NEXT_PUBLIC_BACKEND_V2_SESSION` (and siblings) via switch
- Console TRACE logs at every decision point (see below)
- `.env.local` already has `NEXT_PUBLIC_BACKEND_V2_SESSION=1`

## Console TRACE sequence (after restart)

Filter browser console by `[backendV2.session] TRACE`:

| Log | Meaning |
|-----|---------|
| `TRACE flag { enabled, source, debug }` | Flag resolution |
| `TRACE branch=IF` | Entered RPC path |
| `TRACE branch=ELSE … preventedBy` | **Why RPC skipped** + exact gate |
| `TRACE loadSessionBootstrapForUser() CALLING` | Orchestrator invoked |
| `TRACE SessionRpcBootstrapRepository INSTANTIATING` | Repo constructed |
| `TRACE …loadSessionBootstrap ENTER` | Repo method entered |
| `TRACE supabase.rpc INVOKING { name }` | Network call about to fire |

## Required to verify

1. **Stop and restart** `npm run dev` (env inlining)
2. Hard refresh the browser
3. Log in / reload authenticated app
4. Confirm logs + HAR `.../rpc/rpc_v1_session_bootstrap`
