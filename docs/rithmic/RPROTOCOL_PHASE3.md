# Rithmic Phase 3 — User connection architecture

## Official material audit (0.89.0.0)

| Question | Evidence in supplied package |
|----------|------------------------------|
| What is `RequestLogin.user`? | Optional string field on `request_login.proto` (field 131003). |
| What is `RequestLogin.password`? | Optional string field (130004). |
| Do samples use trader credentials? | **Yes.** `SampleOrder.py` / `SampleBar.py` CLI: `system_name user_id password ...` → assigned to `rq.user` and `rq.password` in `rithmic_login()`. |
| Are vendor env vars in the proto? | **No.** TradeTraxs `RITHMIC_API_USER` / `RITHMIC_API_PASSWORD` are deployment Test API identity, not defined in protos. |
| Does `system_name` vary by broker? | **Yes.** From `RequestRithmicSystemInfo` → `system_name[]`; login requires `system_name` matching the user's environment (Phase 1 proved `"Rithmic Test"`). |
| Multiple systems per gateway? | **Yes.** Phase 1 and samples handle multiple `system_name` values. |
| Third-party app entitlement? | **Not documented** in protos/samples. `app_name` / `app_version` are sent on login but registration/approval process is in `Reference_Guide.pdf` (not machine-readable here). Agreement failures are handled via login `rp_code` (Phase 1). |

### Conclusion for product

**Can an ordinary customer enter normal Rithmic username/password and authorize read-only access via R|Protocol?**

**NOT YET CONFIRMED** for TradeTraxs production.

The **protocol mechanism** supports per-user `user` + `password` login (official samples). What is **not** established from files we hold:

- Whether TradeTraxs must register as an approved `app_name` for each environment
- Whether prop-firm/end-user agreements cover third-party API clients
- Production WSS endpoints and non-Test `system_name` values for live users

Until `RITHMIC_PRODUCTION_USER_AUTH_CONFIRMED=1` (explicit vendor confirmation), UI stays **Test-only** behind `RITHMIC_USER_CONNECT_ENABLED=1`.

## Architecture

- **Multiple connections** per TradeTraxs user (`broker_integration_connections`, unique active `provider_user_id`).
- **Encrypted blob** (`credentials_ciphertext`): `{ kind: "rithmic", username, password, systemName, apiEnvironment: "test" }`.
- **Verify before save:** system info → login → login info → account list → persist.
- **Import (Phase 2):** decrypt per `connection_id`, short-lived session, unchanged fill pipeline.
- **Disconnect:** clear ciphertext, disable broker account rows, preserve trades/executions.
- **Reconnect:** replace ciphertext, keep mappings and checkpoints.

## Email draft for Rithmic

Subject: TradeTraxs — R|Protocol 0.89.0.0 third-party read-only access (Order Plant)

Body:

> We integrate R|Protocol 0.89.0.0 for **read-only** Order Plant use (Account List, Show Fill History — templates 302/303 and 3512/3513). Our Test connectivity uses your Test gateway successfully.
>
> Please confirm:
> 1. May each **end user** provide their own Rithmic **username/password** to our server (over TLS) for `RequestLogin` with our registered `app_name` / `app_version`?
> 2. Is separate **application approval** or entitlement required per FCM/IB or per environment (Test vs Production)?
> 3. Which **WSS URI** and **system_name** values should production prop-firm traders use (vs `rituz00100` / `Rithmic Test`)?
> 4. Are there restrictions on **third-party** read-only API clients regarding user agreements (must users sign in R | Trader first)?
>
> We do not send orders; we only import fill history into a trading journal.

## Feature flags

| Variable | Purpose |
|----------|---------|
| `RITHMIC_USER_CONNECT_ENABLED=1` | Show Connect Rithmic UI + POST `/api/integrations/rithmic/connect` |
| `RITHMIC_PRODUCTION_USER_AUTH_CONFIRMED=1` | Mark vendor-confirmed (metadata only; still require `RITHMIC_API_ENV=test` until production URI is configured) |
| `RITHMIC_PHASE1_API_ENABLED=1` | Unchanged Phase 1 dev discovery |

## Migration

`20260914330000_rithmic_connection_last_verified.sql` — `last_verified_at` on connections.
