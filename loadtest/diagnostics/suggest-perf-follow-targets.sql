-- Read-only: public-ish profiles with recent feed-eligible content (follow these in the app as each perf user).
-- Do not INSERT from SQL Editor as postgres — use normal Follow UI so RLS applies.

select
  p.id as profile_id,
  p.username,
  coalesce(f.cnt, 0) as follower_count,
  coalesce(posts.cnt, 0) as trade_posts_90d
from public.profiles p
left join (
  select following_id, count(*)::int as cnt
  from public.followers
  group by following_id
) f on f.following_id = p.id
left join (
  select user_id, count(*)::int as cnt
  from public.posts
  where created_at > now() - interval '90 days'
  group by user_id
) posts on posts.user_id = p.id
where coalesce(p.is_private, false) = false
  and p.username is not null
order by posts.cnt desc nulls last, f.cnt desc
limit 25;
