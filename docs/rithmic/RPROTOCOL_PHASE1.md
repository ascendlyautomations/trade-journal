# Rithmic R|Protocol — Phase 1

**Package version:** `0.89.0.0` (official `RProtocolAPI.0.89.0.0.zip`)

**Vendor tree:** `third_party/rithmic/0.89.0.0/`

## Proto sources (Phase 1)

Loaded at runtime via **protobufjs** from:

- `third_party/rithmic/0.89.0.0/proto/request_rithmic_system_info.proto`
- `third_party/rithmic/0.89.0.0/proto/response_rithmic_system_info.proto`
- `third_party/rithmic/0.89.0.0/proto/request_login.proto`
- `third_party/rithmic/0.89.0.0/proto/response_login.proto`
- `third_party/rithmic/0.89.0.0/proto/request_login_info.proto`
- `third_party/rithmic/0.89.0.0/proto/response_login_info.proto`
- `third_party/rithmic/0.89.0.0/proto/request_account_list.proto`
- `third_party/rithmic/0.89.0.0/proto/response_account_list.proto`
- `third_party/rithmic/0.89.0.0/proto/request_logout.proto`
- `third_party/rithmic/0.89.0.0/proto/request_heartbeat.proto`
- `third_party/rithmic/0.89.0.0/proto/response_heartbeat.proto`
- `third_party/rithmic/0.89.0.0/samples/samples.py/base.proto` (template routing)

Fill history (Phase 2 only, not implemented):

- `request_show_fill_history.proto` (3512)
- `response_show_fill_history.proto` (3513)

## Runtime

- **Encode/decode:** [protobufjs](https://www.npmjs.com/package/protobufjs) — official `.proto` definitions, no hand-written message shapes.
- **Transport:** [ws](https://www.npmjs.com/package/ws) over **WSS** with CA bundle from `lib/integrations/rithmic/rithmic_ssl_cert_auth_params` (from official `etc/rithmic_ssl_cert_auth_params`).

## Test endpoint

Default (from official `SampleOrder.py` hint): `wss://rituz00100.rithmic.com:443`

Override with `RITHMIC_WSS_URL`. **Must** use `wss://`. `RITHMIC_API_ENV` must be `test`.

## Connection sequence (Phase 1)

1. WSS connect + TLS
2. `RequestRithmicSystemInfo` (template **16**) → `ResponseRithmicSystemInfo` — record `system_name[]` (server may close socket; reconnect for login)
3. `RequestLogin` (template **10**), `infra_type` **ORDER_PLANT (2)** — account list and fill history are Order Plant templates per Reference Guide
4. Success: `ResponseLogin.rp_code` length **1**, value **`"0"`**
5. `RequestLoginInfo` (**300**) → `fcm_id`, `ib_id`, `user_type`
6. `RequestAccountList` (**302**) → multiple `ResponseAccountList` (**303**); end when `rp_code` non-empty
7. `RequestLogout` (**12**), close WebSocket

No market data, orders, or fill import in Phase 1.

## Environment variables (names only)

| Variable | Purpose |
|----------|---------|
| `RITHMIC_API_ENV` | Must be `test` |
| `RITHMIC_API_USER` | Server-side Test user (secret) |
| `RITHMIC_API_PASSWORD` | Server-side Test password (secret) |
| `RITHMIC_WSS_URL` | Optional; default Test WSS URI |
| `RITHMIC_APP_NAME` | Login `app_name` |
| `RITHMIC_APP_VERSION` | Login `app_version` |
| `RITHMIC_TEMPLATE_VERSION` | Login `template_version` (default `3.9` per sample) |
| `RITHMIC_SYSTEM_NAME` | Required when multiple systems returned |
| `RITHMIC_SSL_CA_PATH` | Optional path to official CA params file |
| `RITHMIC_PHASE1_API_ENABLED` | Set to `1` to expose Settings + POST discovery API |

## Code layout

- `lib/integrations/rithmic/rithmicProtocolClient.ts` — wire protocol only
- `lib/integrations/rithmic/runRithmicPhase1Discovery.ts` — orchestration + safe API result
- `npm run rithmic:phase1-discovery` — CLI against env credentials

## Broker schema

- `broker_integration_connections.provider = 'rithmic'`, `api_environment = 'test'`
- `broker_integration_accounts.external_account_id` = `fcm_id|ib_id|account_id`
- Provider-specific fields in `external_metadata` (no Tradovate columns)

Migration: `20260914310000_rithmic_broker_test_environment.sql`

## End-user credentials (TBD)

Phase 1 uses **vendor Test API credentials** in server env. Official samples use **per-trader** `user` + `password` on `RequestLogin`. Production UX will likely require each TradeTraxs user to supply their Rithmic login (stored encrypted server-side). Confirm with Rithmic whether TradeTraxs uses a single API identity or delegated user logins.

Future storage can reuse `INTEGRATION_CREDENTIALS_ENCRYPTION_KEY` + `credentials_ciphertext` by extending the encrypted JSON payload (e.g. username/password fields inside the encrypted blob) — **not** OAuth tokens.

## Phase 2 preview (fills)

Map `ResponseShowFillHistory` into the generic execution ledger:

- Dedupe key candidate: `fill_id` scoped with `fcm_id`, `ib_id`, `account_id` (verify uniqueness in Test)
- Timestamps: `ssboe` / `usecs` / `source_*`
- Economics: `fill_price`, `fill_size`, `transaction_type`, `symbol`, `exchange`
- Checkpoint: `start_index` / `finish_index` / `max_record_count` (≤ 10000)

Then existing flat-to-flat reconstruction → canonical trades → optional `broker_enrichment_status`.

## Agreements

If login fails with agreement-related `rp_code`, users must sign agreements in **R | Trader (Test)** manually — not automated in Phase 1.
