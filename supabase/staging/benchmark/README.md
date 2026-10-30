# Feed `cand` benchmark (isolated)

**Not production.** Uses embedded PostgreSQL 18 on port `55432`.

## Prerequisites

- Node 20+
- `npm install` (includes `pg`, `embedded-postgres` devDependencies)

## Run

```bash
node supabase/staging/benchmark/run-feed-cand-benchmark.mjs
```

### Trade-reel lookup A/B/C (items stage + full RPC)

Compares baseline lateral, lateral + `reels(trade_id, created_at desc, id desc)` partial index, and page-scoped batched `DISTINCT ON` (staging only, embedded PG):

```bash
node supabase/staging/benchmark/run-feed-trade-reel-lookup-benchmark.mjs
```

Report: `artifacts/feed_trade_reel_lookup_benchmark_report.json`

Fair A/B (alternating order, warmed cache) after migration `20261027220000`:

```bash
node supabase/staging/benchmark/run-feed-trade-reel-fair-ab-benchmark.mjs
```

Report: `artifacts/feed_trade_reel_fair_ab_report.json`

Report: `artifacts/feed_cand_benchmark_report.json` (gitignored).

## Staging cloud (`hxlcvffvyadlxcsqxxoy`)

When `supabase/staging/.env.local` defines `TRADETRAXS_STAGING_DATABASE_URL`:

```bash
psql "$TRADETRAXS_STAGING_DATABASE_URL" -v viewer_uuid='…' -v k_limit=9 \
  -f supabase/staging/verify/feed_following_cand_explain_analyze.sql
```

Use `scripts/lib/project-guard.sh` before any write.

## What it validates

- Synthetic viewers with **15 / 40 / 100 / 500** follows
- **Sparse** (~12k posts) and **large** (~350k posts) datasets
- **EXPLAIN (ANALYZE, BUFFERS)** baseline `ANY(v_following)` vs per-followee **LATERAL**
- Row parity (all four branches), cursor page, block filter under **authenticated** + RLS
