# 150-VU timeout runbook — `rpc_v1_feed_bootstrap` (read-only)

Automated Postgres sampling + optional Dashboard logs. **Do not** run `EXPLAIN ANALYZE` on production.

**Expected failure signature:** k6 **HTTP 0** / ~**8001 ms** on `page:feed`; Postgres **`57014`**; **`authenticated.statement_timeout = 8s`**.

---

## One-time setup

1. **Database URL** (Session mode, read-only is enough for `pg_stat_activity`):

   Supabase Dashboard → **Project Settings → Database → Connection string** → **URI** (Session pooler or direct; use a role that can `SELECT` on `pg_stat_activity` — typically the `postgres` user you already use in SQL Editor).

2. Add to **`loadtest/.env.production-perf`** (gitignored):

   ```bash
   TRADETRAXS_PROD_PERF_DATABASE_URL='postgresql://postgres.[ref]:[PASSWORD]@...'
   ```

3. **Install `psql`** (PostgreSQL client) and **`jq`** (validates each sample and writes CSV). If `PGUSER` is set in your shell, **`unset PGUSER`** before sampling so psql uses the user from the URI (or set `PGPASSWORD` when the password is not in the URL).

4. Make the sampler executable (once):

   ```bash
   chmod +x loadtest/diagnostics/sample-onefifty-postgres.sh
   ```

---

## Three commands (recommended layout)

Use **two terminals** (or tmux panes). Repo root: `/Users/TradeTraxs/Developer/trade-journal` (adjust if needed).

### Terminal A — start diagnostics **before** k6

```bash
cd /Users/TradeTraxs/Developer/trade-journal
set -a && source loadtest/.env.production-perf && set +a
./loadtest/diagnostics/sample-onefifty-postgres.sh &
echo $! > loadtest/diagnostics/runs/.sampler.pid
```

Wait **~10 seconds** (several baseline samples at 2s interval). Note paths printed on stderr, e.g.:

- `loadtest/diagnostics/runs/onefifty-pg-<UTC>.jsonl`
- `loadtest/diagnostics/runs/onefifty-pg-<UTC>.csv`
- `loadtest/diagnostics/runs/onefifty-pg-<UTC>.errors.log`

**Optional:** open Supabase **Database → Reports** and **Logs → API / Postgres** for the same wall-clock window.

### Terminal B — run k6 (unchanged workload)

```bash
cd /Users/TradeTraxs/Developer/trade-journal
./loadtest/scripts/verify-production-perf-env.sh
set -a && source loadtest/.env.production-perf && set +a
# Do not run verify immediately before k6 if it just granted 50 auths (Auth 429 risk).
k6 run loadtest/prod-read-perf.js
```

Ensure env has **`LOADTEST_PROD_PERF_MODE=onefifty`**, **`TRADETRAXS_PROD_PERF_ONEFIFTY=yes`**, **50 users** in `LOADTEST_USERS_JSON`, and your chosen **`LOADTEST_WORKLOAD_KIND`**.

### Terminal A — stop diagnostics **after** k6 finishes (+ ~30s wind-down)

```bash
kill -INT "$(cat loadtest/diagnostics/runs/.sampler.pid)"
wait "$(cat loadtest/diagnostics/runs/.sampler.pid)" 2>/dev/null || true
rm -f loadtest/diagnostics/runs/.sampler.pid
```

Sampler prints `Done: N samples → …`. A failed `psql` round **does not** stop the loop; errors append to `*.errors.log` and `sample_error` column in CSV.

---

## Foreground alternative (single operator)

**Terminal A:** run sampler in foreground (no `&`), **Terminal B:** k6. When k6 exits, switch to Terminal A and **Ctrl+C** once.

---

## What the sampler collects (every 2s)

Same logic as [`sample-onefifty-postgres.sql`](./sample-onefifty-postgres.sql) / [`production-feed-readonly.sql`](./production-feed-readonly.sql) §9:

| Field | Meaning |
|--------|---------|
| `connections.*` | Total / active / idle / waiting backends |
| `postgrest.*` | Backends tied to PostgREST / API roles |
| `feed_active` | Active queries matching Feed RPC / `p_scope` PostgREST |
| `feed_running` | Up to 15 active Feed-related queries + `running_for_s` |
| `waits_by_type` | Counts by `wait_event_type` (Lock, IO, …) |
| `longest_active_s` | Longest non-self active query |

**Tune interval:** `ONEFIFTY_SAMPLE_INTERVAL_SEC=2` (default).

---

## Interpret the CSV / JSONL quickly

| Pattern during the 60s stage | Likely cause |
|------------------------------|--------------|
| `conn_active` + `conn_waiting` high; `feed_active` low | **Connection queue** / pool saturation |
| `feed_active` ≥ 5–10 and `longest_active_s` → **8** | **Feed statement timeouts** (57014) |
| `waits_by_type` shows **Lock** | Run lock snapshot below (manual, peak only) |
| Feed + other RPCs fail in **API logs** same second | **Small instance** shared contention |

**Peak lock snapshot** (SQL Editor once, at failure time):

```sql
select blocked.pid,
  round(extract(epoch from (now() - blocked.query_start))::numeric, 2) as blocked_s,
  left(blocked.query, 100) as blocked_q,
  blocking.pid as blocking_pid
from pg_stat_activity blocked
join pg_stat_activity blocking on blocking.pid = any(pg_blocking_pids(blocked.pid))
where blocked.datname = current_database()
  and blocked.wait_event_type = 'Lock';
```

---

## After the run (5 minutes)

1. **Align times:** k6 start/end UTC ↔ first/last `sample_at` in JSONL.
2. **Supabase Logs → Postgres:** search `57014`, `statement timeout`, `too many connections` in that window.
3. **Supabase Logs → API:** `/rest/v1/rpc/rpc_v1_feed_bootstrap` 5xx/504.
4. **Optional SQL** (once, not during load): [`production-feed-readonly.sql`](./production-feed-readonly.sql) §0–2 and `pg_stat_statements` block in the old appendix below.

---

## Appendix — manual SQL & Dashboard (optional)

<details>
<summary>Pre-k6 baseline (SQL Editor)</summary>

```sql
select rolname, rolconfig from pg_roles
where rolname in ('authenticator', 'authenticated', 'anon');

select name, setting from pg_settings
where name in ('max_connections', 'statement_timeout', 'work_mem');
```
</details>

<details>
<summary>Post-run pg_stat_statements (cumulative)</summary>

```sql
select left(query, 80) as q, calls,
  round(mean_exec_time::numeric, 1) as mean_ms,
  round(max_exec_time::numeric, 1) as max_ms
from pg_stat_statements
where query ilike '%rpc_v1_feed_bootstrap%'
  and query not ilike '%pg_stat%'
order by calls desc limit 5;
```
</details>

<details>
<summary>Dashboard checklist</summary>

- **Database → Reports:** peak CPU, memory, connections during sample window  
- **Logs → API:** RPC errors and latency  
- **Logs → Postgres:** `57014`, timeout messages  
</details>

---

## Do not during the test

- `EXPLAIN ANALYZE` on Feed RPC  
- `pg_stat_statements_reset()`  
- Heavy table scans  

---

## Files

| File | Role |
|------|------|
| [`sample-onefifty-postgres.sh`](./sample-onefifty-postgres.sh) | 2s sampler loop |
| [`sample-onefifty-postgres.sql`](./sample-onefifty-postgres.sql) | Read-only query |
| [`production-feed-readonly.sql`](./production-feed-readonly.sql) | Extra one-shot checks |
| [`../PRODUCTION_READ_PERF.md`](../PRODUCTION_READ_PERF.md) | k6 env / onefifty gates |
