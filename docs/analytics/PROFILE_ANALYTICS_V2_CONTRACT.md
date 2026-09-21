# Profile Analytics V2 contract (Phase 7B — server only)

## Tables (not client-readable)

- `trade_public_daily_stats` — daily aggregates for `is_public = true` trades only; same grain and semantics as `trade_daily_stats`.
- `profile_public_analytics_state` — `revision` / `updated_at` for the **public** Profile analytical universe (not `user_analytics_state`).

## RPCs

| RPC | Access | Notes |
|-----|--------|--------|
| `rpc_v1_profile_public_analytics_revision(p_profile_id)` | `authenticated`, `anon` | Tiny payload; visibility gate; `SECURITY DEFINER` reads revision row only when allowed |
| `rpc_v1_profile_analytics_bootstrap_v2(p_profile_id)` | `authenticated`, `anon` | Additive metrics from `trade_public_daily_stats`; equity/streaks/session from one authoritative public trade pass (V1 semantics) |

## Shadow (service_role)

- `profile_public_daily_stats_raw_parity(profile_id, mode)`
- `profile_analytics_v2_shadow_compare(profile_id, viewer_id default null)`
- `profile_analytics_v2_perf_probe(profile_id)` — single-sample timing/bytes only

## Client cutover

**Not wired in Phase 7B.** Production Profile continues to use V1 statistics bootstrap (iOS) and web raw-trade analytics.

## Revision semantics

`profile_public_analytics_state.revision` bumps only when the public Profile universe changes (public trade CRUD, public-affecting field changes, `is_public` toggles, account mode changes when the user has public trades). Private-only edits do not bump.
