-- Feed timeline impressions (ranking input + analytics). Story views remain separate (story_views).

create table if not exists public.feed_content_impressions (
  viewer_id uuid not null references auth.users (id) on delete cascade,
  content_kind text not null,
  content_id uuid not null,
  first_impressed_at timestamptz not null default timezone('utc', now()),
  last_impressed_at timestamptz not null default timezone('utc', now()),
  impression_count integer not null default 1,
  constraint feed_content_impressions_kind_check check (
    content_kind in ('post', 'profile_post', 'achievement_post', 'reel')
  ),
  constraint feed_content_impressions_pkey primary key (viewer_id, content_kind, content_id)
);

create index if not exists feed_content_impressions_viewer_last_idx
  on public.feed_content_impressions (viewer_id, last_impressed_at desc);

comment on table public.feed_content_impressions is
  'Viewer feed impressions for rotating rank (kind|id composite key). SELECT own rows only (ranking); writes via rpc_v1_feed_record_impressions.';

alter table public.feed_content_impressions enable row level security;

drop policy if exists feed_content_impressions_select_own on public.feed_content_impressions;
create policy feed_content_impressions_select_own
  on public.feed_content_impressions
  for select
  to authenticated
  using (viewer_id = auth.uid());

drop policy if exists feed_content_impressions_insert_own on public.feed_content_impressions;
create policy feed_content_impressions_insert_own
  on public.feed_content_impressions
  for insert
  to authenticated
  with check (viewer_id = auth.uid());

drop policy if exists feed_content_impressions_update_own on public.feed_content_impressions;
create policy feed_content_impressions_update_own
  on public.feed_content_impressions
  for update
  to authenticated
  using (viewer_id = auth.uid())
  with check (viewer_id = auth.uid());

grant select, insert, update on table public.feed_content_impressions to authenticated;

-- Impression value frozen at rank session time (survives post-freeze last_impressed_at updates).
create or replace function public._v2_feed_effective_impressed_at(
  p_last_impressed_at timestamptz,
  p_first_impressed_at timestamptz,
  p_rank_frozen_at timestamptz
)
returns timestamptz
language sql
immutable
as $$
  select case
    when p_last_impressed_at is null or p_first_impressed_at is null then null::timestamptz
    when p_last_impressed_at <= p_rank_frozen_at then p_last_impressed_at
    when p_first_impressed_at < p_rank_frozen_at then p_rank_frozen_at - interval '1 microsecond'
    else null::timestamptz
  end;
$$;

comment on function public._v2_feed_effective_impressed_at(timestamptz, timestamptz, timestamptz) is
  'Map mutable impression rows to the viewer state as of p_rank_frozen_at for stable v2 rank.';

revoke all on function public._v2_feed_effective_impressed_at(timestamptz, timestamptz, timestamptz) from public;
grant execute on function public._v2_feed_effective_impressed_at(timestamptz, timestamptz, timestamptz) to authenticated;

-- Composite content key (kind|uuid).
create or replace function public._v2_feed_content_key(p_kind text, p_id uuid)
returns text
language sql
immutable
as $$
  select lower(trim(coalesce(p_kind, ''))) || '|' || p_id::text;
$$;

revoke all on function public._v2_feed_content_key(text, uuid) from public;
grant execute on function public._v2_feed_content_key(text, uuid) to authenticated;

create or replace function public._v2_feed_score(
  p_kind text,
  p_id uuid,
  p_created_at timestamptz,
  p_last_impressed_at timestamptz,
  p_rank_frozen_at timestamptz,
  p_session_seed text
)
returns double precision
language sql
stable
as $$
  with frozen as (
    select coalesce(p_rank_frozen_at, timezone('utc', now())) as ts
  ),
  parts as (
    select
      greatest(
        0.0,
        extract(epoch from ((select ts from frozen) - p_created_at)) / 3600.0
      ) as age_hours,
      case
        when p_last_impressed_at is null then null::double precision
        else greatest(
          0.0,
          extract(
            epoch from (
              (select ts from frozen) - least(p_last_impressed_at, (select ts from frozen))
            )
          ) / 3600.0
        )
      end as hours_since_view,
      public._v2_feed_content_key(p_kind, p_id) as content_key
  )
  select
    (24.0 * exp(-parts.age_hours / 72.0))
    + case when p_last_impressed_at is null then 30.0 else 0.0 end
    - case
        when p_last_impressed_at is null then 0.0
        else 50.0 * exp(-coalesce(parts.hours_since_view, 0.0) / 36.0)
      end
    + (
      (abs(hashtext(coalesce(nullif(trim(p_session_seed), ''), '') || parts.content_key)) % 1000)
      / 10000.0
    )
  from parts;
$$;

comment on function public._v2_feed_score(text, uuid, timestamptz, timestamptz, timestamptz, text) is
  'Frozen-session feed rank score: newer and unseen higher; recently viewed penalized with time decay; light session jitter.';

revoke all on function public._v2_feed_score(text, uuid, timestamptz, timestamptz, timestamptz, text) from public;
grant execute on function public._v2_feed_score(text, uuid, timestamptz, timestamptz, timestamptz, text) to authenticated;

create or replace function public._v2_feed_parse_rank_cursor(p_cursor text)
returns table (
  cursor_score double precision,
  cursor_kind text,
  cursor_id uuid,
  cursor_kind_rank integer
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
  v_parts := string_to_array(p_cursor, '|');
  if coalesce(array_length(v_parts, 1), 0) < 3 then
    return;
  end if;
  cursor_score := v_parts[1]::double precision;
  cursor_kind := lower(trim(v_parts[2]));
  cursor_id := v_parts[3]::uuid;
  cursor_kind_rank := public._v1_feed_kind_rank(cursor_kind);
  return next;
end;
$$;

revoke all on function public._v2_feed_parse_rank_cursor(text) from public;

create or replace function public._v2_feed_before_rank_cursor(
  p_row_score double precision,
  p_row_kind text,
  p_row_id uuid,
  p_cursor_score double precision,
  p_cursor_kind text,
  p_cursor_id uuid,
  p_cursor_kind_rank integer
)
returns boolean
language sql
stable
as $$
  select
    case
      when p_cursor_score is null then true
      when p_row_score < p_cursor_score then true
      when p_row_score > p_cursor_score then false
      when public._v1_feed_kind_rank(p_row_kind) < coalesce(p_cursor_kind_rank, -1) then true
      when public._v1_feed_kind_rank(p_row_kind) > coalesce(p_cursor_kind_rank, -1) then false
      when p_row_id < p_cursor_id then true
      else false
    end;
$$;

revoke all on function public._v2_feed_before_rank_cursor(
  double precision, text, uuid, double precision, text, uuid, integer
) from public;

-- Batch impression recording (debounced server-side).
create or replace function public.rpc_v1_feed_record_impressions(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_item jsonb;
  v_kind text;
  v_id uuid;
  v_count integer := 0;
  v_max integer := 50;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'invalid_items' using errcode = '22023';
  end if;

  if jsonb_array_length(p_items) > v_max then
    raise exception 'batch_too_large' using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_kind := lower(trim(coalesce(v_item ->> 'content_kind', v_item ->> 'kind', '')));
    if v_kind not in ('post', 'profile_post', 'achievement_post', 'reel') then
      continue;
    end if;

    begin
      v_id := (v_item ->> 'content_id')::uuid;
    exception
      when others then
        continue;
    end;

    if v_id is null then
      continue;
    end if;

    if v_kind = 'post' and not exists (select 1 from public.posts p where p.id = v_id) then
      continue;
    elsif v_kind = 'profile_post' and not exists (select 1 from public.profile_posts pp where pp.id = v_id) then
      continue;
    elsif v_kind = 'achievement_post' and not exists (
      select 1 from public.achievement_posts ap where ap.id = v_id
    ) then
      continue;
    elsif v_kind = 'reel' and not exists (select 1 from public.reels r where r.id = v_id) then
      continue;
    end if;

    with upserted as (
      insert into public.feed_content_impressions (
        viewer_id, content_kind, content_id, first_impressed_at, last_impressed_at, impression_count
      )
      values (v_uid, v_kind, v_id, timezone('utc', now()), timezone('utc', now()), 1)
      on conflict (viewer_id, content_kind, content_id) do update
        set
          last_impressed_at = excluded.last_impressed_at,
          impression_count = feed_content_impressions.impression_count + 1
        where feed_content_impressions.last_impressed_at
              < timezone('utc', now()) - interval '30 seconds'
      returning 1
    )
    select v_count + coalesce((select count(*) from upserted), 0) into v_count;
  end loop;

  return jsonb_build_object('recorded', v_count, 'accepted', jsonb_array_length(p_items));
end;
$$;

comment on function public.rpc_v1_feed_record_impressions(jsonb) is
  'Batch feed impressions (max 50). Debounces updates within 30s per row. Non-owners must pass RLS-backed content existence checks.';

revoke all on function public.rpc_v1_feed_record_impressions(jsonb) from public;
grant execute on function public.rpc_v1_feed_record_impressions(jsonb) to authenticated;