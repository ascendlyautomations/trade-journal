-- Minimal dependencies to execute production-shaped rpc_v1_feed_bootstrap in isolated PG.

create or replace function public._v1_feed_kind_rank(p_kind text)
returns integer
language sql
immutable
as $$
  select case p_kind
    when 'post' then 4
    when 'profile_post' then 3
    when 'achievement_post' then 2
    when 'reel' then 1
    else 0
  end;
$$;

create or replace function public._v1_feed_parse_cursor(p_cursor text)
returns table (
  cursor_ts timestamptz,
  cursor_kind text,
  cursor_id uuid,
  cursor_kind_rank integer,
  legacy_only boolean
)
language plpgsql
immutable
as $$
declare
  v_parts text[];
begin
  if p_cursor is null or btrim(p_cursor) = '' then
    return;
  end if;
  if position('|' in p_cursor) > 0 then
    v_parts := string_to_array(p_cursor, '|');
    if coalesce(array_length(v_parts, 1), 0) >= 3 then
      cursor_ts := v_parts[1]::timestamptz;
      cursor_kind := v_parts[2];
      cursor_id := v_parts[3]::uuid;
      cursor_kind_rank := public._v1_feed_kind_rank(cursor_kind);
      legacy_only := false;
      return next;
      return;
    end if;
  end if;
  cursor_ts := p_cursor::timestamptz;
  cursor_kind := null;
  cursor_id := null;
  cursor_kind_rank := null;
  legacy_only := true;
  return next;
end;
$$;

alter table public.profile_posts
  add column if not exists room_id uuid,
  add column if not exists room_name text,
  add column if not exists room_logo text,
  add column if not exists room_description text;

alter table public.achievements
  add column if not exists description text,
  add column if not exists achievement_type text,
  add column if not exists category text,
  add column if not exists badge_key text,
  add column if not exists tier text,
  add column if not exists firm text,
  add column if not exists achieved_at timestamptz,
  add column if not exists image_url text,
  add column if not exists image_crop jsonb,
  add column if not exists value_numeric numeric,
  add column if not exists value_text text;

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

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  image_url text,
  created_at timestamptz not null default now()
);

alter table public.stories enable row level security;
create policy stories_select on public.stories for select to authenticated using (true);

create or replace view public.trades_public_read as
select id, user_id, is_public, created_at, public_description, ticker, direction, pnl, rr
from public.trades;

create or replace function public._v1_feed_post_trade_payload(
  p_trade_id uuid,
  p_reel public.reels,
  p_guest boolean
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select null::jsonb;
$$;

create or replace function public._v1_guest_feed_achievement_projection(p_row public.achievements)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object('id', p_row.id, 'title', p_row.title, 'is_public', true);
$$;

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
  select * from (
    select null::text, null::uuid, 0::bigint, 0::bigint, false::boolean
  ) x
  where false;
$$;

create table if not exists public.likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts (id),
  user_id uuid not null
);

grant execute on function public._v1_feed_kind_rank(text) to authenticated;
grant execute on function public._v1_feed_parse_cursor(text) to authenticated;
grant execute on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) to authenticated;
grant execute on function public._v1_guest_feed_achievement_projection(public.achievements) to authenticated;
grant execute on function public.feed_engagement_counts(uuid[], uuid[], uuid[], uuid[]) to authenticated;

grant select on public.stories to authenticated;
