-- Phase 2 Disk IO: streak/milestone aggregates without client ID dumps + .in() counts.

create or replace function public.user_streak_milestone_bundle(
  p_user_id uuid default auth.uid()
)
returns table (
  onboarding_completed boolean,
  trade_count bigint,
  public_trade_count bigint,
  profile_post_count bigint,
  reel_count bigint,
  comment_count bigint,
  likes_received_count bigint,
  posting_timestamps timestamptz[]
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    coalesce(
      (
        select p.onboarding_completed is true
        from public.profiles p
        where p.id = p_user_id
      ),
      false
    ) as onboarding_completed,

    (
      select count(*)::bigint
      from public.trades t
      where t.user_id = p_user_id
    ) as trade_count,

    (
      select count(*)::bigint
      from public.trades t
      where t.user_id = p_user_id
        and t.is_public is true
    ) as public_trade_count,

    (
      select count(*)::bigint
      from public.profile_posts pp
      where pp.user_id = p_user_id
    ) as profile_post_count,

    (
      select count(*)::bigint
      from public.reels r
      where r.user_id = p_user_id
    ) as reel_count,

    -- Identical to prior client path: comments table only (not trade/profile/reel comments).
    (
      select count(*)::bigint
      from public.comments c
      where c.user_id = p_user_id
    ) as comment_count,

    -- Identical like sources: trade_likes + likes(posts) + profile_post_likes + reel_likes.
    (
      coalesce(
        (
          select count(*)::bigint
          from public.trade_likes tl
          inner join public.trades t on t.id = tl.trade_id
          where t.user_id = p_user_id
        ),
        0
      )
      + coalesce(
        (
          select count(*)::bigint
          from public.likes l
          inner join public.posts po on po.id = l.post_id
          where po.user_id = p_user_id
        ),
        0
      )
      + coalesce(
        (
          select count(*)::bigint
          from public.profile_post_likes ppl
          inner join public.profile_posts pp on pp.id = ppl.profile_post_id
          where pp.user_id = p_user_id
        ),
        0
      )
      + coalesce(
        (
          select count(*)::bigint
          from public.reel_likes rl
          inner join public.reels r on r.id = rl.reel_id
          where r.user_id = p_user_id
        ),
        0
      )
    ) as likes_received_count,

    -- Identical posting activity sources (order irrelevant for weekday Set math).
    coalesce(
      (
        select array_agg(ts)
        from (
          select t.created_at as ts
          from public.trades t
          where t.user_id = p_user_id
            and t.is_public is true
          union all
          select pp.created_at
          from public.profile_posts pp
          where pp.user_id = p_user_id
          union all
          select r.created_at
          from public.reels r
          where r.user_id = p_user_id
        ) x
      ),
      '{}'::timestamptz[]
    ) as posting_timestamps
  where p_user_id = auth.uid();
$$;

comment on function public.user_streak_milestone_bundle(uuid) is
  'Streak milestone signals + posting timestamps for the caller (SECURITY INVOKER).';

grant execute on function public.user_streak_milestone_bundle(uuid) to authenticated;
