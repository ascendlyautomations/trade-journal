-- Staging-only correctness checks: baseline vs per-followee cand (posts branch).
-- Run on hxlcvffvyadlxcsqxxoy after prototype helper or inline SQL is wired.

\set ON_ERROR_STOP on

-- Requires: viewer_uuid, optional blocked_author_uuid fixtures in staging seed.

create or replace function pg_temp._posts_cand_baseline(
  p_viewer uuid,
  p_following uuid[],
  p_block_peers uuid[],
  p_lim int
)
returns table (id uuid, author_id uuid, created_at timestamptz)
language sql stable as $$
  select p.id, p.user_id, p.created_at
  from public.posts p
  where p.user_id is distinct from p_viewer
    and not (p.user_id = any (p_block_peers))
    and public._v1_feed_before_cursor(p.created_at, 'post', p.id, null, null, null, null, false)
    and p.user_id = any (p_following)
  order by p.created_at desc, p.id desc
  limit p_lim;
$$;

create or replace function pg_temp._posts_cand_proposed(
  p_viewer uuid,
  p_following uuid[],
  p_block_peers uuid[],
  p_lim int
)
returns table (id uuid, author_id uuid, created_at timestamptz)
language sql stable as $$
  select x.id, x.author_id, x.created_at
  from (
    select lat.id, lat.author_id, lat.created_at
    from unnest(p_following) fid
    cross join lateral (
      select p.id, p.user_id as author_id, p.created_at
      from public.posts p
      where p.user_id = fid
        and p.user_id is distinct from p_viewer
        and not (p.user_id = any (p_block_peers))
        and public._v1_feed_before_cursor(p.created_at, 'post', p.id, null, null, null, null, false)
      order by p.created_at desc, p.id desc
      limit p_lim
    ) lat
  ) x
  order by x.created_at desc, x.id desc
  limit p_lim;
$$;

-- 1) Row identity match for several viewers (paste UUIDs from staging perf seeds).
-- expect: zero rows returned (except ... except all should be empty)
-- select * from (
--   select * from pg_temp._posts_cand_baseline(v, f, b, 9)
--   except all
--   select * from pg_temp._posts_cand_proposed(v, f, b, 9)
--   union all
--   select * from pg_temp._posts_cand_proposed(v, f, b, 9)
--   except all
--   select * from pg_temp._posts_cand_baseline(v, f, b, 9)
-- ) diff;

-- 2) Tie-break: equal created_at, different id — ensure ORDER BY created_at DESC, id DESC matches.

-- 3) Blocked author: rows from v_block_peers must not appear in either path.

-- 4) Cursor page: set v_cursor_ts/kind/id from first page last row; baseline vs proposed again.

-- 5) Many follows: viewer with cardinality(v_following) > 100 — diff must still be empty.

-- 6) Full RPC parity (after integration):
--    select (a = b) from (
--      select public.rpc_v1_feed_bootstrap('following','all',8,null) a,
--             public.rpc_v1_feed_bootstrap_prototype(...) b  -- only when fork exists
--    ) t;
