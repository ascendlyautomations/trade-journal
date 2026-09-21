# Analytics migration alignment (repo ↔ production)

## Canonical repository migrations (fresh deploy)

Apply in order:

1. `20260921120000_trade_daily_stats_analytical_foundation.sql` — tables, triggers, maintenance, RLS, shadow RPCs, grants (includes service_role-only rebuild revokes).
2. `20260921130000_analytics_shadow_compare_extended.sql` — `analytics_numeric_near`, `analytics_raw_normal_range_metrics`, extended `rpc_v1_analytics_shadow_compare_range`.
3. `20260921140000_analytics_service_role_only_grants.sql` — idempotent grant hardening (safe if already in 21120000).
4. `20260922120000_analytics_phase2_hardening.sql` — parser/`created_at` UTC, revision gating, parity helper, full rebuild.
5. `20260923120000_analytics_calendar_v2_day_trades_rpc.sql` — Calendar V2 day drill-down RPC.
6. `20260923140000_analytics_calendar_day_trades_phase2_signature_fix.sql` — day RPC uses `analytics_calendar_day(..., t.created_at)` (Phase 2 `timestamp` signature).

Production may also list MCP-applied names `analytics_phase2_hardening_body`, `analytics_phase2_hardening_trigger_parity`, `analytics_phase2_parity_rebuild_helpers` (equivalent to §4). Ignore erroneous placeholder `20260922120000_analytics_phase2_hardening` if present (`select 1` only).

## Production MCP history (Phase 1C)

Remote Supabase may also list these **equivalent** names from chunked MCP applies:

- `analytics_shadow_compare_extended_functions`
- `analytics_shadow_compare_rpc_extended`
- `analytics_service_role_only_rebuild_grants`

**No additional SQL** beyond repo files `21130000` + `21140000` is required for parity. Do not add duplicate migrations; use the four repo files above as the single source of truth.

## Fresh-environment checklist

After `supabase db push` / migration apply:

- `trade_daily_stats`, `user_analytics_state` exist
- `trade_daily_stats_grain_uidx` uses `NULLS NOT DISTINCT`
- Trigger `trades_maintain_trade_daily_stats_trg` on `trades`
- Trigger `accounts_rebuild_trade_daily_stats_on_mode_change_trg` on `accounts`
- RPCs: `rpc_v1_analytics_daily_range_bootstrap`, `rpc_v1_analytics_shadow_compare_range`
- Rebuild/backfill: **service_role only** (`authenticated` must not have EXECUTE)
