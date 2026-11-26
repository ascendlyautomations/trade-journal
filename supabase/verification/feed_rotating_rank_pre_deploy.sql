-- Read-only checks after applying:
--   20261126001500_feed_content_impressions.sql
--   20261126003000_rpc_v2_feed_bootstrap.sql
--   20261126010000_feed_rotating_rank_v2_hardening.sql (if 030 already applied)

-- 1) Objects exist
select proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and proname in (
    'rpc_v1_feed_record_impressions',
    'rpc_v2_feed_bootstrap',
    '_v2_feed_score',
    '_v2_feed_parse_rank_cursor'
  )
order by 1;

-- 2) v1 unchanged (still 4-arg signature)
select proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and proname = 'rpc_v1_feed_bootstrap';

-- 3) RLS + SELECT own only (ranking reads)
select c.relname, c.relrowsecurity,
  exists (
    select 1 from pg_policies pol
    where pol.schemaname = 'public'
      and pol.tablename = 'feed_content_impressions'
      and pol.cmd = 'SELECT'
      and pol.policyname = 'feed_content_impressions_select_own'
  ) as has_select_own_policy
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'feed_content_impressions';

-- 3b) v2 invoker + 7-arg catalog (no fragile identity string equality)
select
  p.proname,
  p.pronargs,
  p.prosecdef as is_security_definer,
  not p.prosecdef as is_security_invoker,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('rpc_v1_feed_bootstrap', 'rpc_v2_feed_bootstrap')
order by p.proname;

-- 3c) install helper present
select exists (
  select 1 from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = '_feed_rotating_v2_install_from_v1'
) as has_install_helper;

-- 4) Account delete cascades impressions (FK check)
select conname, confdeltype
from pg_constraint
where conrelid = 'public.feed_content_impressions'::regclass
  and contype = 'f';

-- 5) Frozen snapshot: score unchanged when impression written AFTER frozen_at
--    (replace :viewer with a test user uuid in staging only)
-- with frozen as (select timezone('utc', now()) - interval '1 hour' as t),
-- ins as (
--   insert into feed_content_impressions (viewer_id, content_kind, content_id)
--   values (:viewer, 'profile_post', gen_random_uuid())
--   on conflict do nothing returning last_impressed_at
-- )
-- select public._v2_feed_score(
--   'profile_post', gen_random_uuid(), timezone('utc', now()) - interval '2 days',
--   (select last_impressed_at from ins), (select t from frozen), 'seed'
-- );

-- 6) Rank cursor parse smoke (no DB writes)
select *
from public._v2_feed_parse_rank_cursor('42.5|post|' || gen_random_uuid()::text);