-- Server-side duplicate prevention for engagement actions (double-submit hardening).

-- likes: one like per user per post
with ranked as (
  select
    ctid,
    row_number() over (
      partition by post_id, user_id
      order by created_at asc nulls last, ctid
    ) as rn
  from public.likes
)
delete from public.likes l
using ranked r
where l.ctid = r.ctid
  and r.rn > 1;

create unique index if not exists likes_post_user_unique_idx
  on public.likes (post_id, user_id);

-- followers: one follow edge per pair
with ranked as (
  select
    ctid,
    row_number() over (
      partition by follower_id, following_id
      order by created_at asc nulls last, ctid
    ) as rn
  from public.followers
)
delete from public.followers f
using ranked r
where f.ctid = r.ctid
  and r.rn > 1;

create unique index if not exists followers_pair_unique_idx
  on public.followers (follower_id, following_id);

-- feature requests: one open title per user (case-insensitive)
with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, lower(trim(title))
      order by created_at asc, id
    ) as rn
  from public.feature_requests
)
delete from public.feature_requests fr
using ranked r
where fr.id = r.id
  and r.rn > 1;

create unique index if not exists feature_requests_user_title_unique_idx
  on public.feature_requests (user_id, lower(trim(title)));

-- rooms: one owned room per user
with ranked as (
  select
    id,
    row_number() over (
      partition by owner_user_id
      order by created_at asc nulls last, id
    ) as rn
  from public.rooms
  where owner_user_id is not null
)
delete from public.rooms rm
using ranked r
where rm.id = r.id
  and r.rn > 1;

create unique index if not exists rooms_owner_user_id_unique_idx
  on public.rooms (owner_user_id)
  where owner_user_id is not null;
