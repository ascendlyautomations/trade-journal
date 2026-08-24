-- Phase E2: Profile bootstrap section-level diagnostics (local/staging only).
-- Run with authenticated role + representative JWT claims via Supabase SQL editor
-- or: SET request.jwt.claim.sub = '<viewer-uuid>'; SELECT ...

-- 1) pg_stat_statements for the RPC (read-only; do not reset in production)
SELECT
  calls,
  round(mean_exec_time::numeric, 2) AS mean_ms,
  round(min_exec_time::numeric, 2) AS min_ms,
  round(max_exec_time::numeric, 2) AS max_ms,
  round(total_exec_time::numeric, 2) AS total_ms,
  rows,
  shared_blks_hit,
  shared_blks_read,
  temp_blks_read + temp_blks_written AS temp_blks,
  round((plans / NULLIF(calls, 0))::numeric, 4) AS plans_per_call
FROM pg_stat_statements
WHERE query ILIKE '%rpc_v1_profile_bootstrap%'
ORDER BY total_exec_time DESC
LIMIT 20;

-- 2) Connection / lock / cache health snapshot
SELECT count(*) AS active_connections, state
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state
ORDER BY active_connections DESC;

SELECT
  round(
    100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0),
    2
  ) AS cache_hit_ratio_pct
FROM pg_stat_database
WHERE datname = current_database();

SELECT pid, state, wait_event_type, wait_event, query_start,
       left(query, 120) AS query_preview
FROM pg_stat_activity
WHERE datname = current_database()
  AND state != 'idle'
  AND query NOT ILIKE '%pg_stat_activity%'
ORDER BY query_start ASC
LIMIT 20;

-- 3) EXPLAIN (ANALYZE, BUFFERS) — local/staging only; substitute identifier
-- EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
-- SELECT rpc_v1_profile_bootstrap('example_username', 'trades', 6, NULL);

-- 4) Section timing harness (benchmark-only; not deployed to production RPC)
-- Uncomment and run on local after creating diagnostic function below.

/*
CREATE OR REPLACE FUNCTION rpc_v1_profile_bootstrap_sections_diagnostic(
  p_identifier text,
  p_initial_tab text DEFAULT 'trades',
  p_limit int DEFAULT 6,
  p_cursor text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  t0 timestamptz := clock_timestamp();
  t_profile timestamptz;
  t_viewer timestamptz;
  t_follow timestamptz;
  t_counts timestamptz;
  t_section timestamptz;
  t_stats timestamptz;
  t_trades timestamptz;
  t_engagement timestamptz;
  v_bootstrap jsonb;
BEGIN
  -- Delegate to production RPC then record wall-clock sections separately on replay.
  -- For true section splits, mirror internal CTEs here in staging only.
  SELECT to_jsonb(r) INTO v_bootstrap
  FROM rpc_v1_profile_bootstrap(p_identifier, p_initial_tab, p_limit, p_cursor) r;

  t_profile := clock_timestamp();
  PERFORM 1; -- placeholder: profile resolution timing slot
  t_viewer := clock_timestamp();
  PERFORM 1; -- viewer access / block / privacy
  t_follow := clock_timestamp();
  PERFORM 1; -- follow relationship
  t_counts := clock_timestamp();
  PERFORM 1; -- follower/following counts
  t_section := clock_timestamp();
  PERFORM 1; -- section counts
  t_stats := clock_timestamp();
  PERFORM 1; -- public statistics
  t_trades := clock_timestamp();
  PERFORM 1; -- initial trades page
  t_engagement := clock_timestamp();
  PERFORM 1; -- trade engagement aggregation

  RETURN jsonb_build_object(
    'total_ms', extract(epoch FROM (clock_timestamp() - t0)) * 1000,
    'sections_ms', jsonb_build_object(
      'profile_resolution', extract(epoch FROM (t_profile - t0)) * 1000,
      'viewer_access', extract(epoch FROM (t_viewer - t_profile)) * 1000,
      'follow_state', extract(epoch FROM (t_follow - t_viewer)) * 1000,
      'follow_counts', extract(epoch FROM (t_counts - t_follow)) * 1000,
      'section_counts', extract(epoch FROM (t_section - t_counts)) * 1000,
      'public_stats', extract(epoch FROM (t_stats - t_section)) * 1000,
      'trades_page', extract(epoch FROM (t_trades - t_stats)) * 1000,
      'engagement', extract(epoch FROM (t_engagement - t_trades)) * 1000
    ),
    'found', v_bootstrap->'meta'->>'found'
  );
END;
$$;
*/

-- 5) Index audit helpers (compare predicates vs existing indexes)
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'profiles', 'followers', 'follow_requests', 'trades',
    'trade_likes', 'trade_comments', 'stories', 'rooms'
  )
ORDER BY tablename, indexname;
