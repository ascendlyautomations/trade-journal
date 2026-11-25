-- Optional trade attachment on social comments (all comment tables).
-- Deploy before 20261124250000_trades_select_shared_in_comment.sql (RLS + insert guards).
-- Not applied by agent; deploy when ready.

alter table if exists public.comments
  add column if not exists shared_trade_id uuid null references public.trades (id) on delete set null;

alter table if exists public.trade_comments
  add column if not exists shared_trade_id uuid null references public.trades (id) on delete set null;

alter table if exists public.profile_post_comments
  add column if not exists shared_trade_id uuid null references public.trades (id) on delete set null;

alter table if exists public.achievement_post_comments
  add column if not exists shared_trade_id uuid null references public.trades (id) on delete set null;

alter table if exists public.reel_comments
  add column if not exists shared_trade_id uuid null references public.trades (id) on delete set null;

-- Allow trade-only comments (text optional when a trade is attached).
alter table if exists public.profile_post_comments
  alter column content drop not null;

alter table if exists public.achievement_post_comments
  alter column content drop not null;

alter table if exists public.reel_comments
  alter column content drop not null;

create index if not exists comments_shared_trade_id_idx
  on public.comments (shared_trade_id)
  where shared_trade_id is not null;

create index if not exists trade_comments_shared_trade_id_idx
  on public.trade_comments (shared_trade_id)
  where shared_trade_id is not null;

create index if not exists profile_post_comments_shared_trade_id_idx
  on public.profile_post_comments (shared_trade_id)
  where shared_trade_id is not null;

create index if not exists achievement_post_comments_shared_trade_id_idx
  on public.achievement_post_comments (shared_trade_id)
  where shared_trade_id is not null;

create index if not exists reel_comments_shared_trade_id_idx
  on public.reel_comments (shared_trade_id)
  where shared_trade_id is not null;