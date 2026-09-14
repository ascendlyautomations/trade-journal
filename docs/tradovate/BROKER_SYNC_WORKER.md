# Tradovate automatic sync worker (Phase 5)

## Why this exists

Vercel serverless **cannot** hold a permanent Tradovate user WebSocket. Automatic sync uses:

1. **Long-lived worker** — one `TradovateConnectionAutoSyncSession` per connected OAuth connection.
2. **Official Tradovate user WebSocket** — `wss://{demo|live}.tradovateapi.com/v1/websocket`
   - `authorize` + access token (once per connection)
   - `user/syncrequest` with `{ users: [providerUserId] }`
   - Server **`props`** events (`entityType`: `fill`, `order`, `executionReport`) are **triggers only**
3. **Canonical REST reconciliation** — same `syncTradovateBrokerAccount()` as manual **Sync Now**

Fill.id dedupe + Phase 4 reconstruction remain authoritative.

## Deploy steps (required for automatic sync)

1. Apply migration `20260914270000_broker_auto_sync.sql` (if not already).
2. Provision a **always-on Node process** (examples):
   - Fly.io / Railway / Render worker service
   - ECS/Fargate task
   - Dedicated VM with `systemd`
3. Set environment (same secrets as production web, **never** expose to clients):
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `INTEGRATION_CREDENTIALS_ENCRYPTION_KEY`
   - `TRADOVATE_CLIENT_ID`, `TRADOVATE_CLIENT_SECRET`, `TRADOVATE_API_ENV`
4. From repo root on the worker image:

```bash
npm ci
npm run broker-sync-worker
```

5. Confirm logs emit `{"scope":"tradovate_sync","message":"worker_started"}` and per-connection `connection_session_start`.

## Coalescing

Per mapping: **1.5s debounce**; if sync is in-flight, mark dirty and run **one** follow-up sync after completion.

## Manual Sync Now

Still calls `syncTradovateBrokerAccount({ trigger: "manual" })` — works without the worker.

## Disconnect

When a connection is disconnected in Settings, credentials are cleared and the worker drops the session on its next 60s refresh cycle.
