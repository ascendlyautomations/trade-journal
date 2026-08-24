# Phase A — Session & Dashboard RPC Optimization

Web performance program **Phase A** only. Feed, Messaging, bundle, media, and Realtime phases are **not** started here.

## Status

| Item | State |
|------|--------|
| Migration prepared | `supabase/migrations/20260821180000_rpc_v1_session_dashboard_bootstrap_optimize.sql` |
| Applied to production | **No** — review + staging/local first |
| Contract tests | `lib/backendV2/rpcBootstrapContract.test.ts` |
| Benchmark script | `scripts/benchmark-rpc-bootstrap.mjs` |
| native-ios/ touched | **No** |

---

## A1 — Frozen response contracts

### Deployed function metadata (production snapshot)

| Function | Args | Volatility | Security | Result |
|----------|------|------------|----------|--------|
| `rpc_v1_session_bootstrap()` | none | `stable` | `INVOKER` | `jsonb` |
| `rpc_v1_dashboard_bootstrap(uuid, integer)` | defaults `null`, `500` | `stable` | `INVOKER` | `jsonb` |
| `_v1_session_early_access_active(profiles)` | composite | `stable` | `INVOKER` | `boolean` |
| `_v1_session_is_pro(profiles)` | composite | `stable` | `INVOKER` | `boolean` |

**Grants (unchanged):** `REVOKE ALL FROM public`; `GRANT EXECUTE TO authenticated` on both RPCs.

**search_path:** `public` on both RPCs.

### Contract test fixtures

| Scenario | Fixture |
|----------|---------|
| Pro + accounts + trades | `sessionFixtures.proWithAccounts`, `dashboardFixtures.withTrades` |
| Free user | `sessionFixtures.freeUser` |
| Trial user | `sessionFixtures.trialUser` |
| No accounts | `sessionFixtures.noAccounts`, `dashboardFixtures.noAccounts` |
| No trades | `dashboardFixtures.emptyTrades` |
| Unread DMs | `sessionFixtures.unreadMessages` |
| Golden decode | `fixtures.ts` (existing) |

Validators: `lib/backendV2/rpcContractSchema.ts` — required keys, JSON types, null vs `[]` rules.

---

## A2 — Internal cost breakdown (before optimization)

Source: deployed SQL (migrations `20260819180000`, `20260820211500`), `pg_stat_statements`, plain `EXPLAIN`, table stats (~322 trades, ~324 notifications, ~16 conversation participants).

### Session RPC — sequential sections (old)

| Section | Tables | Pattern | Relative cost |
|---------|--------|---------|---------------|
| Profile lookup | `profiles` | PK | Low |
| Admin / affiliate | `admin_users`, `affiliates` | 2× `EXISTS` | Low |
| Notification prefs | `notification_preferences` | PK optional row | Low |
| Accounts summary | `accounts` | `jsonb_agg` — **no user_id+created_at index** | Low today, scales with accounts |
| Following | `followers` | `jsonb_agg` — `followers_pair_unique_idx` | Low |
| Social unread | `notifications` | `count(*)` + type filter | Medium (partial unread index exists) |
| **DM unread** | `cp`, `prefs`, `messages` | **LEFT JOIN all messages → GROUP BY conversation** | **Highest planner cost** |
| JSON assembly | — | plpgsql sequential round trips (~8) | **Platform latency multiplier** |

**pg_stat_statements:** mean ~669ms, max ~4,983ms (57 calls).

**HAR server-wait:** 2.6–6.1s — not payload (receive &lt;2ms). Small table sizes → delay is **DB execution + pool/planner + concurrent login RPC contention**, not row volume.

### Dashboard RPC — sequential sections (old)

| Section | Trades scan | Notes |
|---------|-------------|-------|
| Accounts | — | Duplicate with Session; cheap at current scale |
| Trade count | 1× full user/account filter | |
| Trade window JSON | 1× up to 500 rows, all columns | Large payload build |
| Metrics | 2× filter + backtest exclude | |
| Equity window | 3× same filtered set + window fn | |
| Payout | `account_payout_cycles` | Low |
| Oldest created | 4× count path overlap | |

**pg_stat_statements:** mean ~825ms, max ~3,692ms (34 calls).

---

## A3/A4 — SQL architecture (after optimization)

### Session — before

```
plpgsql: auth → profile → 6 separate SELECT INTO → jsonb_build → return
(~8 server round trips inside one function call)
DM: LEFT JOIN messages × participants → GROUP BY conversation_id
```

### Session — after

```
plpgsql: auth check → single SELECT building full jsonb
  FROM profiles p
  CROSS JOIN LATERAL (admin + affiliate EXISTS)
  LEFT JOIN LATERAL accounts_agg
  LEFT JOIN LATERAL following_agg
  LEFT JOIN LATERAL social_unread_count
  LEFT JOIN LATERAL dm_unread (CROSS JOIN LATERAL per-conversation count)
  LEFT JOIN LATERAL notification_preferences
```

**DM change:** per-conversation `CROSS JOIN LATERAL (SELECT count(*) FROM messages WHERE conversation_id = cp...)` — index-friendly `messages_conversation_sender_idx` / `messages_conversation_id_created_at_idx`, avoids materializing full message×participant join before aggregate.

### Dashboard — before

```
4+ separate passes over trades (count, window, metrics, equity, min)
+ accounts + payout
```

### Dashboard — after

```
WITH scoped_trades AS MATERIALIZED (...),
     live_trades AS MATERIALIZED (backtest filter),
     trade_stats, trade_window_json, metrics_json, equity_json,
     accounts_json, payout_json, recent_json
→ single jsonb_build_object
```

One materialized scan for scoped trades; live subset reused for metrics + equity.

---

## A5 — Duplicated accounts work

**Decision: Option A** — keep both RPC contracts unchanged; optimize each aggregation.

- Session `accounts_summary` and Dashboard `accounts` serve different consumers and shapes.
- Dashboard must not depend on Session success (prior global-loading regressions).
- At ~32 accounts project-wide, duplicate aggregation is not the primary bottleneck; trade scans and sequential session round trips were.

---

## Indexes

| Index | Action | Justification |
|-------|--------|---------------|
| `accounts_user_id_created_at_idx` | **ADD** | Both RPCs `ORDER BY created_at ASC, id ASC WHERE user_id = ?`; previously only unique on `(user_id, lower(name))` |
| `trades_user_id_created_at_idx` | retain | Window + equity ordering |
| `conversation_participants_user_id_idx` | retain | DM participant filter |
| `messages_conversation_id_created_at_idx` | retain | Lateral unread counts |
| `notifications_user_id_unread_idx` | retain | Social unread partial index |
| New partial notification type index | **not added** | Existing unread partial index sufficient at current scale; revisit if `EXPLAIN` shows seq scan at scale |

**Rollback index:**

```sql
DROP INDEX IF EXISTS public.accounts_user_id_created_at_idx;
```

---

## A6 — Migration safety

**File:** `20260821180000_rpc_v1_session_dashboard_bootstrap_optimize.sql`

- `CREATE OR REPLACE FUNCTION` — same signatures
- `SECURITY INVOKER` preserved
- `search_path = public` preserved
- Grants re-applied explicitly
- No RLS policy changes
- Index uses `IF NOT EXISTS` — idempotent

### Rollback instructions

1. Re-apply function bodies from:
   - Session: `supabase/migrations/20260819180000_rpc_v1_session_bootstrap.sql`
   - Dashboard: `supabase/migrations/20260820211500_rpc_v1_dashboard_bootstrap_account_id_boundary.sql`
2. Drop index: `DROP INDEX IF EXISTS public.accounts_user_id_created_at_idx;`
3. Re-run `npm run test:backend-v2`

Or run rollback migration (create manually from those files if needed):

```bash
# After Supabase CLI is available:
supabase db push --dry-run   # verify
supabase migration repair    # if needed
```

**Do not edit** already-applied migrations `20260819180000`, `20260819200000`, `20260820211500`.

---

## A7 — Performance test

### Before (production pg_stat_statements)

| RPC | Mean | Max |
|-----|------|-----|
| Session | ~669 ms | ~4,983 ms |
| Dashboard | ~825 ms | ~3,692 ms |

### After (expected — validate on staging)

Run:

```bash
SUPABASE_URL=... BENCHMARK_USER_JWT=... node scripts/benchmark-rpc-bootstrap.mjs
```

**Targets:** Session warm median &lt;150ms, Dashboard &lt;250ms; neither routinely &gt;1s.

If targets missed after migration, profile with `EXPLAIN (ANALYZE, BUFFERS)` on **staging** for:

- Session DM lateral block
- Dashboard `scoped_trades` materialization
- Concurrent Session+Dashboard from cold pool

---

## A8 — Application regression

App layer unchanged — RPC names, args, and JSON contracts identical.

Manual checklist after staging apply:

- [ ] Login / hard refresh
- [ ] Dashboard: no accounts, multi-account, account filter, date/mode filters
- [ ] Metrics + equity + recent trades
- [ ] Free / trial / pro / admin badges
- [ ] Session failure → Dashboard legacy path still works
- [ ] Dashboard failure → no forced logout

Automated:

```bash
npm run test:backend-v2   # includes Phase A contract tests
npm run build
npm run lint
```

---

## RLS / security verification

- Both functions remain **`SECURITY INVOKER`** — all reads subject to existing RLS.
- No `SECURITY DEFINER` escalation.
- No `user_metadata` authorization.
- DM unread still scoped to `conversation_participants.user_id = auth.uid()`; lateral counts only messages in those conversations.
- No new EXECUTE grants beyond `authenticated`.

---

## Remaining bottlenecks (post Phase A)

1. **Feed bootstrap** (~1.49s HAR) — Phase B
2. **Messaging bootstrap** (~3.33s HAR) — Phase B
3. **Concurrent cold RPC launch** at login — may still spike if pool cold; not addressed by serialization (explicitly out of scope)
4. **Trade window payload** — up to 500 full rows still serialized; column reduction requires contract/UI audit
5. **Accounts duplicated** — acceptable per Option A until scale demands Option B versioned param

---

## Files changed (Phase A)

| File | Purpose |
|------|---------|
| `supabase/migrations/20260821180000_rpc_v1_session_dashboard_bootstrap_optimize.sql` | Optimized RPCs + index |
| `lib/backendV2/rpcContractSchema.ts` | Shape validators |
| `lib/backendV2/rpcContractFixtures.ts` | Scenario fixtures |
| `lib/backendV2/rpcBootstrapContract.test.ts` | Contract tests |
| `scripts/benchmark-rpc-bootstrap.mjs` | Staging benchmark |
| `docs/backend-v2/PHASE_A_RPC_OPTIMIZATION.md` | This document |
| `package.json` | Test script update |
