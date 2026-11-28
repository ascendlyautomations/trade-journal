-- Corrective pass after story archive / private bucket deploy (production audit 2026-11-28).
-- Wrapped in a single transaction: policy drop → column type → policy restore → storage/RPC updates.

begin;

-- ---------------------------------------------------------------------------
-- 1. Drop RLS policies that reference stories.created_at (blocks ALTER TYPE)
--    pg_depend: only policy stories_select_visible on production (2026-11-28).
-- ---------------------------------------------------------------------------

drop policy if exists "stories_select_visible" on public.stories;

-- ---------------------------------------------------------------------------
-- 2. stories.created_at → timestamptz (idempotent; UTC preservation)
-- ---------------------------------------------------------------------------

do $story_created_at$
declare
  v_data_type text;
begin
  select c.data_type
  into v_data_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'stories'
    and c.column_name = 'created_at';

  if v_data_type = 'timestamp without time zone' then
    alter table public.stories
      alter column created_at type timestamptz
      using (
        case
          when created_at is null then null::timestamptz
          else created_at at time zone 'UTC'
        end
      );
  elsif v_data_type is distinct from 'timestamp with time zone' then
    raise exception 'story_private_storage_audit: unexpected stories.created_at type %', v_data_type;
  end if;
end;
$story_created_at$;

alter table public.stories
  alter column created_at set default now();

comment on column public.stories.created_at is
  'Story creation instant (UTC). Public 24h window and owner archive cutoffs use this column.';

-- ---------------------------------------------------------------------------
-- 3. Restore stories_select_visible (20261125130000_story_engagement.sql intent)
-- ---------------------------------------------------------------------------

create policy "stories_select_visible"
  on public.stories
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or (
      public.story_is_publicly_active(stories.created_at)
      and (auth.uid() is null or not (stories.user_id = any (public.rls_viewer_block_peer_ids())))
      and (
        exists (
          select 1
          from public.profiles p
          where p.id = stories.user_id
            and coalesce(p.is_private, false) = false
        )
        or (
          auth.uid() is not null
          and exists (
            select 1
            from public.followers f
            where f.following_id = stories.user_id
              and f.follower_id = auth.uid()
          )
        )
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 4. story_is_publicly_active overload for plain timestamp (defensive callers)
-- ---------------------------------------------------------------------------

create or replace function public.story_is_publicly_active(p_created_at timestamp without time zone)
returns boolean
language sql
stable
set search_path = public
as $$
  select public.story_is_publicly_active((p_created_at at time zone 'UTC'));
$$;

comment on function public.story_is_publicly_active(timestamp without time zone) is
  'Wrapper for legacy timestamp reads; stories.created_at is timestamptz after 20261128160000.';

revoke all on function public.story_is_publicly_active(timestamp without time zone) from public;
grant execute on function public.story_is_publicly_active(timestamp without time zone) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Storage SELECT: drop legacy public-bucket policies; keep gateway policy
-- ---------------------------------------------------------------------------

drop policy if exists "Public read access for stories" on storage.objects;
drop policy if exists "stories_select_all" on storage.objects;
drop policy if exists "stories_storage_select" on storage.objects;

create policy "stories_storage_select"
  on storage.objects
  for select
  to anon, authenticated
  using (
    bucket_id = 'stories'
    and public.story_storage_object_readable(name)
  );

comment on policy "stories_storage_select" on storage.objects is
  'Private stories bucket: object readable when owner or active public story rules pass.';

-- ---------------------------------------------------------------------------
-- 6. RPC payloads: ISO8601 UTC text for created_at
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_story_for_viewer(p_story_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_row public.stories%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_row
  from public.stories s
  where s.id = p_story_id;

  if not found then
    return null;
  end if;

  if not public.viewer_can_see_story_row(v_row) then
    return null;
  end if;

  return jsonb_build_object(
    'id', v_row.id,
    'user_id', v_row.user_id,
    'image_url', v_row.image_url,
    'storage_path', v_row.storage_path,
    'resolved_storage_path', public.story_row_storage_path(v_row),
    'created_at', to_char(v_row.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.USOF'),
    'text_overlays', coalesce(v_row.text_overlays, '[]'::jsonb)
  );
end;
$$;

comment on function public.rpc_v1_story_for_viewer(uuid) is
  'Returns a story row when the caller may view it (24h public rules or owner archive).';

revoke all on function public.rpc_v1_story_for_viewer(uuid) from public;
grant execute on function public.rpc_v1_story_for_viewer(uuid) to authenticated;

create or replace function public.rpc_v1_owner_story_archive(
  p_limit integer default 60,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_rows jsonb := '[]'::jsonb;
  v_cutoff timestamptz := now() - interval '24 hours';
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.created_at desc), '[]'::jsonb)
  into v_rows
  from (
    select
      s.id,
      s.user_id,
      s.image_url,
      s.storage_path,
      public.story_row_storage_path(s) as resolved_storage_path,
      to_char(s.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.USOF') as created_at,
      coalesce(s.text_overlays, '[]'::jsonb) as text_overlays
    from public.stories s
    where s.user_id = v_uid
      and s.created_at <= v_cutoff
    order by s.created_at desc
    limit greatest(1, least(coalesce(p_limit, 60), 200))
    offset greatest(coalesce(p_offset, 0), 0)
  ) t;

  return jsonb_build_object('stories', v_rows);
end;
$$;

comment on function public.rpc_v1_owner_story_archive(integer, integer) is
  'Owner-only expired stories for Settings → Story Archive.';

revoke all on function public.rpc_v1_owner_story_archive(integer, integer) from public;
grant execute on function public.rpc_v1_owner_story_archive(integer, integer) to authenticated;

create or replace function public.rpc_v1_story_dm_media_access(p_story_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_row public.stories%rowtype;
  v_allowed boolean := false;
  v_reason text := 'unavailable';
begin
  if auth.uid() is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  select * into v_row
  from public.stories s
  where s.id = p_story_id;

  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'not_found');
  end if;

  if v_row.user_id = auth.uid() then
    v_allowed := true;
    v_reason := 'owner';
  elsif public.story_is_publicly_active(v_row.created_at)
        and public.viewer_can_see_story_row(v_row) then
    v_allowed := true;
    v_reason := 'active_public';
  end if;

  return jsonb_build_object(
    'allowed', v_allowed,
    'reason', v_reason,
    'id', v_row.id,
    'user_id', v_row.user_id,
    'created_at', to_char(v_row.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.USOF'),
    'storage_path', public.story_row_storage_path(v_row),
    'image_url', v_row.image_url
  );
end;
$$;

comment on function public.rpc_v1_story_dm_media_access(uuid) is
  'Authorizes story media for DM previews and deep links.';

revoke all on function public.rpc_v1_story_dm_media_access(uuid) from public;
grant execute on function public.rpc_v1_story_dm_media_access(uuid) to authenticated;

commit;