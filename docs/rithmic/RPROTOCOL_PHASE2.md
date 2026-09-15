# Rithmic Phase 2 — Manual fill import (Test)

## Scope

- **Read-only** `RequestShowFillHistory` (3512) / `ResponseShowFillHistory` (3513) on existing ORDER_PLANT login path.
- Persists normalized rows in `broker_integration_executions`, reconstructs via shared `tradeReconstruction.ts` (`lifecycleProvider: "rithmic"`), upserts canonical trades with `import_source = rithmic`.
- **No** worker, polling, orders, or market data.

## Production user credentials

Phase 2 on Test uses **server env** credentials (`RITHMIC_API_*`). End-user username/password must not be collected in UI until the credential model (encrypt with `INTEGRATION_CREDENTIALS_ENCRYPTION_KEY`, store in `credentials_ciphertext` only) is product-approved.

## Real Test checklist

1. Apply migration `20260914320000_broker_execution_text_ids.sql` (text fill IDs + `provider_sync_state`).
2. Settings → Rithmic → **Run & save accounts** → link/create TradeTraxs account.
3. Place a simulated trade in R | Trader (Test).
4. **Import New Trades** → verify one canonical trade (symbol, qty, entry/exit, timestamps).
5. Add RR/notes → import again → **zero** duplicates, enrichment preserved.

## P&L and fees

Fill history provides price/size and timestamps; **no** authoritative per-fill commission in 3513. `valuePerPoint` is not resolved in Phase 2 — monetary P&L stays null unless future reference-data requests supply contract multipliers.
