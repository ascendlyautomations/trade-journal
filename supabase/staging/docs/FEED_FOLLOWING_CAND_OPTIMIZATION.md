# Following Feed — `cand` CTE optimization prototype

**Status:** Staging/local prototype only (not applied to production).

## Problem (production evidence)

| Signal | 50 VU | 75 VU |
|--------|-------|-------|
| HTTP failures | 0% | 1.36% |
| Feed first-page p95 | ~544ms | **8001ms** (k6 client timeout) |
| Postgres `57014` on feed `cand` | — | **13** in load minute |
| Feed pagination / dashboard | Healthy | Healthy (p95 ≪ 8s) |

First-page Following uses `p_cursor = null` → `_v1_feed_before_cursor` is true for all candidates → each of four branches scans/sorts the **full followee set** then `LIMIT v_limit+1`. Under concurrent load, that work runs inside `rpc_v1_feed_bootstrap` until **`authenticated.statement_timeout` (8s)**.

Block-peers-once (`20261027120000`) is already live; remaining hot path is **Following first-page `cand`**.

## Current shape (production)

Four `UNION ALL` branches (posts, profile_posts, achievement_posts, reels). Each branch:

```sql
WHERE (v_scope = 'following' AND user_id = ANY(v_following))
  AND block / before_cursor / guest / filter predicates
ORDER BY created_at DESC, id DESC
LIMIT v_limit + 1
```

Then `ranked` window sort across merged candidates (≤ 4×(v_limit+1) rows).

**RLS:** RPC remains **SECURITY INVOKER**; predicates must stay in-branch (no definer shortcut for content).

## Proposed change (Following scope only)

For **`v_scope = 'following'`** and **`cardinality(v_following) > 0`**, replace each branch’s `ANY(v_following)` scan with:

1. `unnest(v_following)` → **`CROSS JOIN LATERAL`**  
2. Per followee: **`WHERE user_id = fid`** + same predicates + **`ORDER BY created_at DESC, id DESC LIMIT v_limit + 1`**  
3. Merge lateral rows: **`ORDER BY created_at DESC, id DESC LIMIT v_limit + 1`**

**Global** and **guest** paths keep the existing `ANY`/anti-following logic unchanged.

### Semantics (per branch)

For a fixed content kind, let **K = v_limit + 1**. For each author *a* in `v_following`, let **S(a,K)** be the *K* newest rows from *a* matching filters. Then:

\[
\text{GlobalTopK}\big(\bigcup_a \text{rows}(a)\big) \subseteq \bigcup_a S(a,K)
\]

Any row in the global top-*K* from author *a* is among *a*’s *K* newest matching rows. Merging all **S(a,K)**, sorting, and taking top-*K* yields the same set as the current single sort over all followee rows.

**Pagination:** Unchanged — still uses `_v1_feed_before_cursor` inside each lateral arm.

**Mixed kinds / final cursor:** Unchanged — `ranked` still applies `_v1_feed_kind_rank` across the four branch outputs.

### Plan intuition

| Scale | Baseline (observed) | Proposed |
|-------|---------------------|----------|
| Small DB | Often `posts_created_at_idx` + membership check | Multiple small sorts; may be neutral |
| Large DB + many followees | Large sort / hash over all followee rows | **Index `(user_id, created_at DESC)`** probe per followee, bounded rows |

Production read-only **EXPLAIN (no ANALYZE)** on tiny data (Oct 2026): baseline used **Index Scan on `posts_created_at_idx`** + join to `followers`; lateral used **per-followee seq scan** (table ~38 rows). **Do not extrapolate** — run **EXPLAIN ANALYZE** on staging clone.

### Tradeoffs

| Benefit | Cost |
|---------|------|
| Bounded rows per branch: **O(|following| × (v_limit+1))** before merge | **|following|** lateral loops (e.g. 500 → 4500 rows max per branch before final limit) |
| Better index use at scale | Slightly more SQL/planner work per RPC |
| Targets 75-VU `57014` on `cand` | Must replicate for **four** branches; RPC diff is non-trivial |
| | **Global** path untouched — two code paths to maintain until unified |

**Not a substitute** for connection/compute headroom (`max_connections=60` vs 75+ VUs) if queueing dominates.

## Files

| Path | Purpose |
|------|---------|
| `supabase/staging/prototypes/feed_following_cand_per_followee.sql` | Prototype helper + integration sketch |
| `supabase/staging/verify/feed_following_cand_explain_analyze.sql` | **EXPLAIN ANALYZE** baseline vs proposed |
| `supabase/staging/verify/feed_following_cand_equivalence.sql` | Row-level diff + fixture checklist |

## Embedded benchmark results (2026-10-27)

Isolated **embedded Postgres 18** harness: `node supabase/staging/benchmark/run-feed-cand-benchmark.mjs`  
Report: `supabase/staging/benchmark/artifacts/feed_cand_benchmark_report.json`

| Scale | Posts | Viewer follows | Posts branch baseline | Proposed | Speedup |
|-------|-------|----------------|----------------------|----------|---------|
| sparse | 12k | 15 | ~69ms | ~1ms | ~71× |
| sparse | 12k | 40 | ~67ms | ~2ms | ~30× |
| sparse | 12k | 100 | ~63ms | ~5ms | ~12× |
| sparse | 12k | 500 | ~43ms | ~17ms | ~2.4× |
| **large** | **350k** | **15** | **~2048ms** | **~1ms** | **~2190×** |
| **large** | **350k** | **40** | **~2034ms** | **~2ms** | **~881×** |
| **large** | **350k** | **100** | **~2054ms** | **~6ms** | **~369×** |
| large | 350k | 500 | ~44ms | ~27ms | ~1.6× |

- **Equivalence:** zero row diffs (baseline vs proposed) for all four branches, cursor page, sparse + large.
- **Blocks:** blocked followee excluded under authenticated + RLS.
- **Buffers (example, large / 15 follows / posts):** baseline ~2.8M shared hits vs proposed ~2.3k (plan JSON aggregate).
- **Regression pocket:** at **500 follows** on **350k posts**, proposed still wins (~1.6×) but margin narrows (500× lateral loops).

**Cloud staging (`hxlcvffvyadlxcsqxxoy`):** not connected in this run (no credentials in repo); re-run `feed_following_cand_explain_analyze.sql` on full clone before production apply.

## Staging execution plan (when clone available)

1. Apply prototype helper on **hxlcvffvyadlxcsqxxoy** only (`project-guard.sh`).
2. Pick 3 viewers: ~15 follows (perf), ~100 follows, ~500 follows (if seeded).
3. Run `feed_following_cand_explain_analyze.sql` — record **Execution Time**, **Buffers**, **rows** for baseline vs proposed on **posts** branch, then profile/achievement/reels.
4. Run equivalence SQL (`EXCEPT ALL` empty) first page + cursor page + blocked peer fixture.
5. Optional: fork `rpc_v1_feed_bootstrap` → `_prototype` and diff full JSON for 50 random viewers.
6. If posts branch wins on clone, integrate all four branches behind `v_scope = 'following'` and re-run load test on staging only.

## Forward migration (20261027140000)

| Artifact | Purpose |
|----------|---------|
| `supabase/migrations/20261027140000_feed_following_cand_per_followee.sql` | DO-block patch (idempotent; fail-closed guards) |
| `supabase/migrations/rollback/20261027140000_feed_following_cand_per_followee_rollback.sql` | Restore pre-migration `pg_get_functiondef` (prod-verified anchors) |
| `node supabase/staging/benchmark/run-migration-do-isolated.mjs` | Embedded PG: apply migration **twice**, RPC parity, rollback smoke |
| `node supabase/staging/benchmark/run-migration-fail-closed.mjs` | Missing `get_active_block_peer_ids` prerequisite |
| `lib/privacy/feedFollowingCandPerFollowee.migration.contract.test.ts` | Anchor + rollback artifact contracts |

**Note:** Global-branch `UNION ALL` arms wrap `ORDER BY … LIMIT` in parentheses (required for valid `CREATE FUNCTION`).

## Production constraints (this effort)

- **No** production SQL apply, **no** EXPLAIN ANALYZE on production.
- **No** load-test config changes.
- Integrate via forward migration only after staging clone gate (`hxlcvffvyadlxcsqxxoy`).
