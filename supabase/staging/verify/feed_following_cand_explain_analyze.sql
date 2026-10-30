-- Staging-only: EXPLAIN (ANALYZE, BUFFERS) for Following first-page posts `cand` branch.
-- Target: hxlcvffvyadlxcsqxxoy (never fobudrkniacatvilbofw).
--
-- Prerequisites:
--   - Full clone or representative staging data (see supabase/staging/full-clone/)
--   - Viewer with 10–500 follows and non-empty Following feed
--
-- Usage:
--   psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -v viewer_uuid='...' -v k_limit=9 \
--     -f supabase/staging/verify/feed_following_cand_explain_analyze.sql

\set ON_ERROR_STOP on

-- Simulate authenticated invoker (adjust if using real JWT via PostgREST).
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'viewer_uuid', true);

create temp table _feed_cand_ctx on commit drop as
select
  :'viewer_uuid'::uuid as v_uid,
  coalesce(
    (select array_agg(f.following_id order by f.following_id)
     from public.followers f
     where f.follower_id = :'viewer_uuid'::uuid),
    '{}'::uuid[]
  ) as v_following,
  coalesce(
    (select public.get_active_block_peer_ids()),
    '{}'::uuid[]
  ) as v_block_peers,
  (:k_limit::int + 1) as lim,
  null::timestamptz as v_cursor_ts,
  null::text as v_cursor_kind,
  null::uuid as v_cursor_id,
  null::int as v_cursor_kind_rank,
  false as v_cursor_legacy,
  false as v_guest,
  true as v_include_trades;

\echo '=== BASELINE (ANY + sort + limit) — posts branch ==='
explain (analyze, buffers, verbose, costs)
select p.id, p.user_id, p.created_at
from public.posts p, _feed_cand_ctx c
where c.v_include_trades
  and p.user_id is distinct from c.v_uid
  and not (p.user_id = any (c.v_block_peers))
  and public._v1_feed_before_cursor(
    p.created_at, 'post', p.id,
    c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
  )
  and p.user_id = any (c.v_following)
order by p.created_at desc, p.id desc
limit (select lim from _feed_cand_ctx);

\echo '=== PROPOSED (per-followee lateral + merge sort + limit) — posts branch ==='
explain (analyze, buffers, verbose, costs)
select x.id, x.user_id, x.created_at
from _feed_cand_ctx c
cross join unnest(c.v_following) as fid
cross join lateral (
  select p.id, p.user_id, p.created_at
  from public.posts p
  where c.v_include_trades
    and p.user_id = fid
    and p.user_id is distinct from c.v_uid
    and not (p.user_id = any (c.v_block_peers))
    and public._v1_feed_before_cursor(
      p.created_at, 'post', p.id,
      c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
    )
  order by p.created_at desc, p.id desc
  limit (select lim from _feed_cand_ctx)
) x
order by x.created_at desc, x.id desc
limit (select lim from _feed_cand_ctx);

\echo '=== Repeat for profile_posts, achievement_posts, reels (copy pattern) ==='
\echo '=== Full RPC: explain (analyze, buffers) select rpc_v1_feed_bootstrap(''following'',''all'', 8, null); only after prototype merged ==='

rollback;
