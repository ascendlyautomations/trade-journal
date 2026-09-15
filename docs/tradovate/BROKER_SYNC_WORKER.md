# Tradovate automatic sync worker (Phase 5)

## AUTO SYNC ROOT CAUSE (production)

**Vercel only deploys the Next.js web app.** It does **not** start `broker-sync-worker`.

Automatic sync requires a **separate always-on Node process** that holds the Tradovate user WebSocket. Without that process:

- No `user/syncrequest` subscription
- No `props` events → no debounced calls to `syncTradovateBrokerAccount()`
- Manual **Sync Now** still works (Phase 4 REST on demand)

Settings → **Worker offline** means `listener_worker_heartbeat_at` is missing or stale (>90s).

## Architecture

1. **Worker** (`services/tradovate-sync-worker/run.ts`) — one session per connected OAuth connection.
2. **Tradovate WebSocket** — `wss://{demo|live}.tradovateapi.com/v1/websocket`
   - `authorize` + access token
   - `user/syncrequest` with `{ users: [providerUserId] }`
   - **`e: "props"`** (`fill`, `order`, `executionReport`) = **triggers only**
3. **Canonical sync** — `syncTradovateBrokerAccount()` (same as manual Sync Now). Fill.id ledger + Phase 4 reconstruction unchanged.

## Worker entry point

| Item | Value |
|------|--------|
| Entry | `services/tradovate-sync-worker/run.ts` |
| npm script | `npm run broker-sync-worker` |
| Docker | `services/tradovate-sync-worker/Dockerfile` (build from repo root) |

## Required environment variable **names**

Same as production web (service role + Tradovate OAuth secrets):

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `INTEGRATION_CREDENTIALS_ENCRYPTION_KEY`
- `TRADOVATE_CLIENT_ID`
- `TRADOVATE_CLIENT_SECRET`
- `TRADOVATE_API_ENV` (`demo` or `live`)

Optional: `NODE_ENV=production`

## Deploy steps (you must do this for auto sync)

1. Apply Supabase migrations through `20260914280000_broker_sync_worker_heartbeat.sql`.
2. Choose an **always-on** host (not Vercel): Fly.io, Railway, Render worker, ECS, VM + systemd, etc.
3. Deploy the repo (or Docker image) with the env vars above.
4. Start **one** worker instance (scale to 1 unless you add distributed locking later):

```bash
npm ci
npm run broker-sync-worker
```

Docker (from repository root):

```bash
docker build -f services/tradovate-sync-worker/Dockerfile -t tradetraxs-broker-sync .
docker run --env-file /path/to/worker.env tradetraxs-broker-sync
```

5. Verify logs (stdout JSON, no tokens):

   - `{"scope":"tradovate_sync","message":"worker_started",...}`
   - `connection_session_start` per Tradovate connection
   - `connection_authenticated` / `subscription_established`
   - After a Tradovate fill: `tradovate_props_event` → `sync_started` → `sync_success`

6. In TradeTraxs Settings → Tradovate, connection should show **Listener connected** (heartbeat fresh).

## Verify listener is alive

| Check | How |
|--------|-----|
| Process | Worker container/VM process running `broker-sync-worker` |
| Logs | `worker_started`, `connection_authenticated` |
| Database | `broker_integration_connections.listener_worker_heartbeat_at` updates every ~45s |
| UI | Settings → Tradovate → **Listener connected** (not **Worker offline**) |

## Coalescing & recovery

- Per mapping: **1.5s debounce**; in-flight sync → one follow-up after completion.
- **Startup** and **WebSocket reconnect** → full reconciliation for all auto-sync mappings.
- Token refresh uses connection-scoped credentials; reconnect required if refresh fails.

## Manual Sync Now

Unchanged — `syncTradovateBrokerAccount({ trigger: "manual" })`. Does not require the worker.

## Client bridge (not auto sync)

`BrokerImportedTradesRealtimeBridge` only refreshes the **browser trade cache** when the worker inserts trades via Supabase Realtime. It does **not** connect to Tradovate.
