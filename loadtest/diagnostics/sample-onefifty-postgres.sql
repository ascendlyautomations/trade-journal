-- Read-only single-row sample for 150-VU Postgres diagnostics.
-- Invoked by sample-onefifty-postgres.sh every 2s (do not run in a tight loop in SQL Editor).

select jsonb_build_object(
  'sample_at', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'connections', (
    select jsonb_build_object(
      'total', count(*),
      'active', count(*) filter (where state = 'active'),
      'idle', count(*) filter (where state = 'idle'),
      'idle_in_transaction', count(*) filter (where state = 'idle in transaction'),
      'waiting', count(*) filter (where wait_event_type is not null)
    )
    from pg_stat_activity
    where datname = current_database()
  ),
  'postgrest', (
    select jsonb_build_object(
      'total', count(*),
      'active', count(*) filter (where state = 'active'),
      'idle', count(*) filter (where state = 'idle')
    )
    from pg_stat_activity
    where datname = current_database()
      and (
        application_name ilike '%postgrest%'
        or usename in ('authenticator', 'authenticated', 'anon')
      )
  ),
  'feed_active', (
    select count(*)
    from pg_stat_activity
    where datname = current_database()
      and state = 'active'
      and (
        query ilike '%rpc_v1_feed_bootstrap%'
        or query ilike '%pgrst%feed%'
        or (query ilike '%pgrst_call%' and query ilike '%p_scope%')
      )
  ),
  'feed_running', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'running_for_s', round(extract(epoch from (now() - query_start))::numeric, 2),
      'wait_type', wait_event_type,
      'wait_event', wait_event,
      'role', usename,
      'app', left(coalesce(application_name, ''), 40)
    ) order by query_start), '[]'::jsonb)
    from pg_stat_activity
    where datname = current_database()
      and state = 'active'
      and pid <> pg_backend_pid()
      and (
        query ilike '%rpc_v1_feed_bootstrap%'
        or query ilike '%feed_engagement_counts%'
        or (query ilike '%pgrst_call%' and query ilike '%p_scope%')
      )
    limit 15
  ),
  'waits_by_type', (
    select coalesce(jsonb_object_agg(wait_event_type, cnt), '{}'::jsonb)
    from (
      select wait_event_type, count(*)::int as cnt
      from pg_stat_activity
      where datname = current_database()
        and wait_event_type is not null
      group by 1
    ) w
  ),
  'longest_active_s', (
    select round(max(extract(epoch from (now() - query_start)))::numeric, 2)
    from pg_stat_activity
    where datname = current_database()
      and state = 'active'
      and pid <> pg_backend_pid()
  )
) as sample;
