-- Attach public trades + trade-linked reels to a subset of feed posts (staging benchmark only).

alter table public.reels
  add column if not exists video_url text,
  add column if not exists thumbnail_url text,
  add column if not exists duration_seconds integer,
  add column if not exists kind text;

alter table public.trades
  add column if not exists public_description text,
  add column if not exists ticker text,
  add column if not exists direction text,
  add column if not exists pnl numeric,
  add column if not exists rr numeric;

create index if not exists reels_trade_id_idx
  on public.reels (trade_id)
  where trade_id is not null;

with candidates as (
  select
    p.id as post_id,
    p.user_id,
    p.created_at,
    gen_random_uuid() as new_trade_id
  from public.posts p
  where p.trade_id is null
    and mod(abs(hashtext(p.id::text)), 5) = 0
  limit 12000
),
ins_trades as (
  insert into public.trades (id, user_id, is_public, created_at, ticker, direction, pnl, rr)
  select
    c.new_trade_id,
    c.user_id,
    true,
    c.created_at,
    'ES',
    'long',
    100,
    2
  from candidates c
  returning id
),
upd_posts as (
  update public.posts p
  set trade_id = c.new_trade_id
  from candidates c
  where p.id = c.post_id
  returning p.id
)
insert into public.reels (
  user_id,
  trade_id,
  created_at,
  visibility,
  video_url,
  thumbnail_url,
  duration_seconds
)
select
  c.user_id,
  c.new_trade_id,
  c.created_at + interval '30 seconds',
  'public',
  'https://cdn.example/bench/reel.mp4',
  'https://cdn.example/bench/thumb.jpg',
  12
from candidates c;

-- Second reel on ~2% of linked trades (Feed must pick newest by created_at).
insert into public.reels (
  user_id,
  trade_id,
  created_at,
  visibility,
  video_url,
  thumbnail_url,
  duration_seconds
)
select
  p.user_id,
  p.trade_id,
  p.created_at + interval '2 hours',
  'public',
  'https://cdn.example/bench/reel-newer.mp4',
  'https://cdn.example/bench/thumb-newer.jpg',
  15
from public.posts p
where p.trade_id is not null
  and mod(abs(hashtext(p.trade_id::text)), 50) = 0;

analyze public.trades;
analyze public.posts;
analyze public.reels;
