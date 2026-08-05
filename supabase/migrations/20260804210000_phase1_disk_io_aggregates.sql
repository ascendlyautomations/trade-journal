-- Phase 1 Disk IO: aggregate RPCs for feed engagement + explore.
-- SECURITY INVOKER so existing RLS on likes/comments/trades/followers still applies.
-- Identical semantics to prior client-side row dumps / 3000-row explore window.

-- ---------------------------------------------------------------------------
-- Feed: like + comment counts + liked-by-me for visible content IDs
-- ---------------------------------------------------------------------------
create or replace function public.feed_engagement_counts(
  p_post_ids uuid[] default '{}',
  p_profile_post_ids uuid[] default '{}',
  p_achievement_post_ids uuid[] default '{}',
  p_reel_ids uuid[] default '{}'
)
returns table (
  content_type text,
  content_id uuid,
  like_count bigint,
  comment_count bigint,
  liked_by_me boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  with
  post_likes as (
    select
      l.post_id as content_id,
      count(*)::bigint as like_count,
      bool_or(l.user_id = auth.uid()) as liked_by_me
    from public.likes l
    where cardinality(p_post_ids) > 0
      and l.post_id = any (p_post_ids)
    group by l.post_id
  ),
  post_comments as (
    select
      c.post_id as content_id,
      count(*)::bigint as comment_count
    from public.comments c
    where cardinality(p_post_ids) > 0
      and c.post_id = any (p_post_ids)
    group by c.post_id
  ),
  profile_likes as (
    select
      l.profile_post_id as content_id,
      count(*)::bigint as like_count,
      bool_or(l.user_id = auth.uid()) as liked_by_me
    from public.profile_post_likes l
    where cardinality(p_profile_post_ids) > 0
      and l.profile_post_id = any (p_profile_post_ids)
    group by l.profile_post_id
  ),
  profile_comments as (
    select
      c.profile_post_id as content_id,
      count(*)::bigint as comment_count
    from public.profile_post_comments c
    where cardinality(p_profile_post_ids) > 0
      and c.profile_post_id = any (p_profile_post_ids)
    group by c.profile_post_id
  ),
  achievement_likes as (
    select
      l.achievement_post_id as content_id,
      count(*)::bigint as like_count,
      bool_or(l.user_id = auth.uid()) as liked_by_me
    from public.achievement_post_likes l
    where cardinality(p_achievement_post_ids) > 0
      and l.achievement_post_id = any (p_achievement_post_ids)
    group by l.achievement_post_id
  ),
  achievement_comments as (
    select
      c.achievement_post_id as content_id,
      count(*)::bigint as comment_count
    from public.achievement_post_comments c
    where cardinality(p_achievement_post_ids) > 0
      and c.achievement_post_id = any (p_achievement_post_ids)
    group by c.achievement_post_id
  ),
  reel_likes as (
    select
      l.reel_id as content_id,
      count(*)::bigint as like_count,
      bool_or(l.user_id = auth.uid()) as liked_by_me
    from public.reel_likes l
    where cardinality(p_reel_ids) > 0
      and l.reel_id = any (p_reel_ids)
    group by l.reel_id
  ),
  reel_comments as (
    select
      c.reel_id as content_id,
      count(*)::bigint as comment_count
    from public.reel_comments c
    where cardinality(p_reel_ids) > 0
      and c.reel_id = any (p_reel_ids)
    group by c.reel_id
  )
  select
    'post'::text,
    coalesce(pl.content_id, pc.content_id),
    coalesce(pl.like_count, 0),
    coalesce(pc.comment_count, 0),
    coalesce(pl.liked_by_me, false)
  from post_likes pl
  full outer join post_comments pc on pc.content_id = pl.content_id

  union all

  select
    'profile_post'::text,
    coalesce(pl.content_id, pc.content_id),
    coalesce(pl.like_count, 0),
    coalesce(pc.comment_count, 0),
    coalesce(pl.liked_by_me, false)
  from profile_likes pl
  full outer join profile_comments pc on pc.content_id = pl.content_id

  union all

  select
    'achievement_post'::text,
    coalesce(pl.content_id, pc.content_id),
    coalesce(pl.like_count, 0),
    coalesce(pc.comment_count, 0),
    coalesce(pl.liked_by_me, false)
  from achievement_likes pl
  full outer join achievement_comments pc on pc.content_id = pl.content_id

  union all

  select
    'reel'::text,
    coalesce(pl.content_id, pc.content_id),
    coalesce(pl.like_count, 0),
    coalesce(pc.comment_count, 0),
    coalesce(pl.liked_by_me, false)
  from reel_likes pl
  full outer join reel_comments pc on pc.content_id = pl.content_id;
$$;

comment on function public.feed_engagement_counts(uuid[], uuid[], uuid[], uuid[]) is
  'Aggregated like/comment counts + liked-by-me for feed cards (SECURITY INVOKER).';

grant execute on function public.feed_engagement_counts(uuid[], uuid[], uuid[], uuid[])
  to authenticated;

-- ---------------------------------------------------------------------------
-- Explore: aggregate the same global recent-public window (default 3000 rows)
-- into per-user summaries + session/ticker frequencies (no raw trade dump).
-- ---------------------------------------------------------------------------
create or replace function public.explore_trade_meta_aggregates(
  p_limit int default 3000
)
returns table (
  row_kind text,
  user_id uuid,
  trade_count bigint,
  win_count bigint,
  total_pnl numeric,
  last_trade_at timestamptz,
  session text,
  ticker text,
  freq bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with recent as (
    select
      t.user_id,
      t.session,
      t.ticker,
      t.created_at,
      t.pnl
    from public.trades t
    where t.is_public = true
    order by t.created_at desc
    limit greatest(least(coalesce(p_limit, 3000), 10000), 1)
  ),
  summaries as (
    select
      r.user_id,
      count(*)::bigint as trade_count,
      count(*) filter (
        where r.pnl is not null and r.pnl::numeric > 0
      )::bigint as win_count,
      coalesce(sum(r.pnl::numeric) filter (where r.pnl is not null), 0) as total_pnl,
      max(r.created_at) as last_trade_at
    from recent r
    group by r.user_id
  ),
  sessions as (
    select
      r.user_id,
      r.session::text as session,
      count(*)::bigint as freq
    from recent r
    where r.session is not null
      and length(trim(r.session::text)) > 0
    group by r.user_id, r.session::text
  ),
  tickers as (
    select
      r.user_id,
      upper(trim(r.ticker::text)) as ticker,
      count(*)::bigint as freq
    from recent r
    where r.ticker is not null
      and length(trim(r.ticker::text)) > 0
    group by r.user_id, upper(trim(r.ticker::text))
  )
  select
    'summary'::text,
    s.user_id,
    s.trade_count,
    s.win_count,
    s.total_pnl,
    s.last_trade_at,
    null::text,
    null::text,
    null::bigint
  from summaries s

  union all

  select
    'session'::text,
    s.user_id,
    null::bigint,
    null::bigint,
    null::numeric,
    null::timestamptz,
    s.session,
    null::text,
    s.freq
  from sessions s

  union all

  select
    'ticker'::text,
    t.user_id,
    null::bigint,
    null::bigint,
    null::numeric,
    null::timestamptz,
    null::text,
    t.ticker,
    t.freq
  from tickers t;
$$;

comment on function public.explore_trade_meta_aggregates(int) is
  'Explore trade meta from the same recent-public window as the prior 3000-row client pull, returned as aggregates.';

grant execute on function public.explore_trade_meta_aggregates(int)
  to authenticated;
grant execute on function public.explore_trade_meta_aggregates(int)
  to anon;

-- ---------------------------------------------------------------------------
-- Explore: follower / following counts for a profile id batch (GROUP BY)
-- ---------------------------------------------------------------------------
create or replace function public.explore_social_counts(p_profile_ids uuid[])
returns table (
  profile_id uuid,
  followers_count bigint,
  following_count bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with ids as (
    select distinct unnest(coalesce(p_profile_ids, '{}'::uuid[])) as profile_id
  ),
  followers as (
    select
      f.following_id as profile_id,
      count(*)::bigint as followers_count
    from public.followers f
    where cardinality(p_profile_ids) > 0
      and f.following_id = any (p_profile_ids)
    group by f.following_id
  ),
  following as (
    select
      f.follower_id as profile_id,
      count(*)::bigint as following_count
    from public.followers f
    where cardinality(p_profile_ids) > 0
      and f.follower_id = any (p_profile_ids)
    group by f.follower_id
  )
  select
    i.profile_id,
    coalesce(fr.followers_count, 0),
    coalesce(fo.following_count, 0)
  from ids i
  left join followers fr on fr.profile_id = i.profile_id
  left join following fo on fo.profile_id = i.profile_id;
$$;

comment on function public.explore_social_counts(uuid[]) is
  'Per-profile follower/following counts for Explore batches (no edge row dump).';

grant execute on function public.explore_social_counts(uuid[])
  to authenticated;
grant execute on function public.explore_social_counts(uuid[])
  to anon;
