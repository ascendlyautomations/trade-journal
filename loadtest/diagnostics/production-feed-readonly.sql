-- TradeTraxs — read-only production diagnostics for rpc_v1_feed_bootstrap latency
-- Run manually in Supabase SQL Editor during or after a load test window.
-- Do NOT run EXPLAIN ANALYZE on production without operator approval (executes the query).

-- ---------------------------------------------------------------------------
-- 0) API statement timeout (PostgREST uses authenticator / authenticated roles)
-- ---------------------------------------------------------------------------
select rolname, rolconfig
from pg_roles
where rolname in ('authenticator', 'authenticated');

-- Expected on Supabase: statement_timeout=8s (matches k6 REQUEST_TIMEOUT and SQLSTATE 57014).

-- ---------------------------------------------------------------------------
-- 1) Connection pressure (instant snapshot)
-- ---------------------------------------------------------------------------
select
  count(*) filter (where state = 'active') as active_backends,
  count(*) filter (where wait_event_type is not null) as waiting,
  count(*) as total_backends
from pg_stat_activity
where datname = current_database();

select
  usename,
  application_name,
  state,
  wait_event_type,
  wait_event,
  left(query, 120) as query_prefix,
  now() - query_start as running_for
from pg_stat_activity
where datname = current_database()
  and pid <> pg_backend_pid()
order by query_start nulls last
limit 40;

-- ---------------------------------------------------------------------------
-- 2) Long-running queries touching feed tables (if any stuck > 5s)
-- ---------------------------------------------------------------------------
select
  pid,
  now() - query_start as duration,
  left(query, 200) as query_prefix
from pg_stat_activity
where datname = current_database()
  and state = 'active'
  and query_start < now() - interval '5 seconds'
  and (
    query ilike '%rpc_v1_feed_bootstrap%'
    or query ilike '%from public.posts%'
    or query ilike '%feed_engagement_counts%'
  )
order by query_start;

-- ---------------------------------------------------------------------------
-- 3) Index presence (expected from migrations 20260820224542, 20260804230000)
-- ---------------------------------------------------------------------------
select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('posts', 'profile_posts', 'achievement_posts', 'reels', 'followers', 'user_blocks')
order by tablename, indexname;

-- ---------------------------------------------------------------------------
-- 4) Table scale (cardinality drives global feed branch cost)
-- ---------------------------------------------------------------------------
select 'posts' as rel, count(*)::bigint as rows from public.posts
union all
select 'profile_posts', count(*)::bigint from public.profile_posts
union all
select 'achievement_posts', count(*)::bigint from public.achievement_posts
union all
select 'reels', count(*)::bigint from public.reels
union all
select 'followers', count(*)::bigint from public.followers;

-- ---------------------------------------------------------------------------
-- 5) EXPLAIN (no ANALYZE) — substitute a real test user uuid for :viewer_id
-- Simulates global / all / limit 8 / first page (matches loadtest feedBootstrapBody default).
-- Review plan for: four branch limits, users_have_active_block per row, merge sort.
-- ---------------------------------------------------------------------------
-- begin;
-- set local role authenticated;
-- set local request.jwt.claim.sub = '<viewer-uuid>';
-- explain (verbose, costs, buffers off)
-- select public.rpc_v1_feed_bootstrap('global', 'all', 8, null);
-- rollback;

-- ---------------------------------------------------------------------------
-- 6) EXPLAIN (no ANALYZE) — second page with cursor from a prior response next_cursor
-- ---------------------------------------------------------------------------
-- explain (verbose, costs, buffers off)
-- select public.rpc_v1_feed_bootstrap(
--   'global',
--   'all',
--   8,
--   '2025-01-01T00:00:00.000Z|post|<uuid-from-last-item>'
-- );

-- ---------------------------------------------------------------------------
-- 7) Block-check helper cost (called per candidate row in feed SQL)
-- ---------------------------------------------------------------------------
-- explain (verbose, costs, buffers off)
-- select public.users_have_active_block('<viewer-uuid>'::uuid, '<author-uuid>'::uuid);

-- ---------------------------------------------------------------------------
-- 8) PostgREST pool — use Supabase Dashboard → Database → Reports / API logs
-- (not available via SQL). Correlate API 5xx/504 spikes with k6 client_timeout lines.

-- ---------------------------------------------------------------------------
-- 9) During-load lightweight sample (run every 5–10s manually during k6)
-- Full workflow: loadtest/diagnostics/onefifty-vu-timeout-runbook.md
-- ---------------------------------------------------------------------------
-- select jsonb_build_object(
--   'sample_at', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
--   'connections', (
--     select jsonb_build_object(
--       'total', count(*),
--       'active', count(*) filter (where state = 'active'),
--       'idle', count(*) filter (where state = 'idle'),
--       'waiting', count(*) filter (where wait_event_type is not null)
--     )
--     from pg_stat_activity where datname = current_database()
--   ),
--   'feed_active', (
--     select count(*) from pg_stat_activity
--     where datname = current_database() and state = 'active'
--       and (query ilike '%rpc_v1_feed_bootstrap%'
--            or (query ilike '%pgrst_call%' and query ilike '%p_scope%'))
--   ),
--   'waits_by_type', (
--     select coalesce(jsonb_object_agg(wait_event_type, cnt), '{}'::jsonb)
--     from (
--       select wait_event_type, count(*)::int as cnt
--       from pg_stat_activity
--       where datname = current_database() and wait_event_type is not null
--       group by 1
--     ) w
--   )
-- ) as sample;
