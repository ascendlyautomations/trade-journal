-- Grandfather profiles that already use TradeTraxs but still have onboarding_completed=false.
-- Native blocking onboarding uses the same gate as web (profiles.onboarding_completed).
--
-- Criteria (any one qualifies):
--   * at least one trade
--   * at least one profile wall post
--   * at least one follow relationship (follower or following)
--   * at least one trade-room membership
--
-- Verify before/after in staging:
--   select count(*) from public.profiles p
--   where coalesce(p.onboarding_completed, false) = false
--     and (exists (select 1 from public.trades t where t.user_id = p.id)
--       or exists (select 1 from public.profile_posts pp where pp.user_id = p.id)
--       or exists (select 1 from public.followers f where f.follower_id = p.id or f.following_id = p.id)
--       or exists (select 1 from public.room_members rm where rm.user_id = p.id));

update public.profiles p
set onboarding_completed = true
where coalesce(p.onboarding_completed, false) = false
  and (
    exists (select 1 from public.trades t where t.user_id = p.id)
    or exists (select 1 from public.profile_posts pp where pp.user_id = p.id)
    or exists (
      select 1
      from public.followers f
      where f.follower_id = p.id
         or f.following_id = p.id
    )
    or exists (select 1 from public.room_members rm where rm.user_id = p.id)
  );

comment on column public.profiles.onboarding_completed is
  'True after profile onboarding completes (username + trader fields). Grandfathered for active legacy users.';
