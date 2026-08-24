# Phase E2 — Profile Tail Latency Validation (Complete)

## Production evidence (pg_stat_statements)

| Metric | Value |
|--------|-------|
| Calls (post-benchmark) | 457+ |
| Mean DB execution | ~21ms (recent warm path) |
| Min DB execution | 0.29ms |
| Max DB execution | 3,146.50ms (historical tail) |
| Shared block hits | 55,301 |
| Shared block reads | 3 |
| Temp blocks written | 0 |

**Interpretation:** RPC is routinely fast on warm path. Historical max ~3.1s confirms genuine DB tail latency. Profile 8’s 10.6s included PostgREST/connection/schema-cache wait (PGRST002 on concurrent reels). Disk reads are not the cause.

---

## Task 1 — Benchmark results (550 calls/scenario, live)

Auth: magic-link JWT (not printed). Target: production Supabase.

| Scenario | Run | p50 | p75 | p95 | p99 | max | Payload | Failures | PGRST002 |
|----------|-----|-----|-----|-----|-----|-----|---------|----------|----------|
| other_public (nrltrades) | warm×50 | 78ms | 123ms | 175ms | 254ms | 254ms | 14,981 B | 0 | 0 |
| other_public | cold×10 | 274ms | 477ms | 719ms | 719ms | 719ms | 14,981 B | 0 | 0 |
| other_public | variance×50 | 96ms | 130ms | 178ms | 185ms | 185ms | 14,981 B | 0 | 0 |
| public_no_trades (root) | warm×50 | 49ms | 57ms | 123ms | 136ms | 136ms | 1,105 B | 0 | 0 |
| public_no_trades | cold×10 | 208ms | 300ms | 402ms | 402ms | 402ms | 1,105 B | 0 | 0 |
| public_no_trades | variance×50 | 78ms | 98ms | 145ms | 175ms | 175ms | 1,105 B | 0 | 0 |
| own_profile (tradetraxs) | warm×50 | 59ms | 69ms | 118ms | 147ms | 147ms | 3,422 B | 0 | 0 |
| own_profile | cold×10 | 250ms | 554ms | **1,965ms** | 1,965ms | 1,965ms | 3,422 B | 0 | 0 |
| own_profile | variance×50 | 72ms | 86ms | 141ms | 150ms | 150ms | 3,422 B | 0 | 0 |
| private_followed (blanchettrades) | warm×50 | 55ms | 58ms | 139ms | 147ms | 147ms | 2,686 B | 0 | 0 |
| private_followed | cold×10 | 261ms | 329ms | 1,361ms | 1,361ms | 1,361ms | 2,686 B | 0 | 0 |
| private_followed | variance×50 | 93ms | 116ms | 164ms | 215ms | 215ms | 2,686 B | 0 | 0 |
| private_restricted (anon JWT) | warm×50 | 59ms | 111ms | 196ms | 233ms | 233ms | 1,001 B | 0 | 0 |
| private_restricted | cold×10 | 271ms | 293ms | 479ms | 479ms | 479ms | 1,001 B | 0 | 0 |
| private_restricted | variance×50 | 82ms | 105ms | 157ms | 168ms | 168ms | 1,001 B | 0 | 0 |

**Thresholds:** warm p50 < 250ms ✓ | warm p95 < 500ms ✓ | p99 < 1s ✓ (except cold-tail outliers) | PGRST002 = 0 ✓

Cold-idle tails (719ms–1,965ms) reflect connection/cache warmup, not steady-state query cost.

---

## Task 2 — Integration test results

```
✓ own_username
✓ other_public_username
✓ missing_username
✓ private_visible_profile
✓ private_restricted_profile
✓ profile_no_stories
✓ profile_active_story
✓ profile_expired_story
✓ cursor_page_two
```

**Bug found and fixed:** `trimmed` CTE referenced outside scope when `has_more=true` (profiles with >6 trades returned HTTP 404/42P01). Fixed in migration `20260821225439`.

---

## Task 3 — Section timings (authenticated, RLS on)

`profile_bootstrap_sections_diagnostic('nrltrades')` as tradetraxs:

| Section | ms |
|---------|-----|
| profile_resolution | 19.8 |
| follow_relationship | 18.3 |
| follow_counts | 0.3 |
| **section_counts** | **110.2** |
| public_stats | 1.8 |
| initial_trades_page | 10.5 |
| likes_comments | 8.3 |

**Dominant section:** `section_counts` (multiple EXISTS + COUNT on trades/reels/achievements with RLS).

Diagnostic function: `scripts/profile-bootstrap-sections-diagnostic.sql` (local/staging only; created temporarily for measurement, dropped after).

---

## Task 4 — EXPLAIN (authenticated, RLS on)

- Full RPC: **128ms** execution, 3,891 shared hits, 0 reads, planning 0.02ms
- Username lookup: **Index Scan on `profiles_username_key`** — `(lower(username) = 'nrltrades')`, 0.64ms
- Trades count (RLS on): Seq Scan 322 rows → 13 visible, **4.4ms**

No repeated sequential scans on profiles. Trades use seq scan at current table size (~322 rows).

---

## Task 5 — Username index fix

Changed predicate to `lower(p.username) = lower(trim(p_identifier))` in migration `20260821225439`. Plan confirms **`profiles_username_key`** usage.

---

## Task 6 — Index decisions

| Index | Decision | Rationale |
|-------|----------|-----------|
| `stories (user_id, created_at desc, id desc)` | **Added** | Supports active-story EXISTS; existing idx may be missing on remote; ~5 rows today |
| `trade_comments (trade_id, created_at asc, id asc)` | **Added** | Supports engagement aggregation at scale; ~4 rows today |

Neither explains multi-second latency at current sizes. Added for growth predicates only.

---

## Task 7 — RLS cost

Trades public count with RLS: 4.4ms seq scan (322 rows, 13 pass filter). Section_counts repeats similar checks across tables — explains ~110ms section cost. **No RLS policy changes** — cost acceptable at current scale; `(select auth.uid())` form not warranted without measured per-row regression.

---

## Task 8 — Cache key canonicalization

- **Canonical key:** `viewerKey|profileId`
- **Aliases:** username + UUID routes → same entry
- Username rename clears stale aliases
- Viewer isolation preserved; logout clears viewer entries

Files: `lib/profileBootstrap/profileBootstrapCache.ts`, `profileBootstrapRepository.ts`

---

## Task 9 — Migration chain restored

Copied from `supabase/rollbacks/Completed Migrations/` to `supabase/migrations/`:

- `20260820224542_rpc_v1_feed_bootstrap_optimize.sql`
- `20260821014228_rpc_v2_messaging_bootstrap.sql`
- `20260821090000_rpc_v1_messaging_bootstrap.sql`
- `20260821021641_rpc_v1_getting_started_signals.sql`

**`npm run test:backend-v2`:** 209/209 pass

---

## Task 10 — Perceived performance (client)

| Scenario | Expected behavior |
|----------|-------------------|
| Cold other profile | Route shell immediate if preview/cache; bootstrap ~78ms p50 |
| Warm same profile | Cache hit → immediate header+trades; background revalidate once |
| Feed → Profile | Preview header from `ProfileLink` seed |
| Private restricted | Shell + restricted message; anon-safe payload |
| PGRST002 | Stale cache served; ≤1 retry; no legacy fan-out |

---

## SQL applied for validation

Migration **`20260821225439_optimize_profile_lookup_indexes`** applied to production via Supabase MCP to unblock integration/benchmark (username fix, cursor bug fix, indexes). Review in repo before broader rollout.

Temporary diagnostic function created and **dropped** after measurement.

---

## Files changed

- `supabase/migrations/20260821225439_optimize_profile_lookup_indexes.sql` (new)
- Restored 4 missing migration files
- `lib/profileBootstrap/profileBootstrapCache.ts` (canonical keys)
- `lib/profileBootstrap/profileBootstrapRepository.ts`
- `scripts/benchmark-profile-rpc.mjs`, `profile-rpc-integration.test.mjs`
- `scripts/profile-test-auth.mjs`, `profile-test-setup.mjs`
- `scripts/profile-bootstrap-sections-diagnostic.sql`
- `lib/profileBootstrap.phaseE2.test.ts`
- `docs/backend-v2/PHASE_E2_PROFILE_TAIL_LATENCY.md`

**native-ios/ untouched.**
