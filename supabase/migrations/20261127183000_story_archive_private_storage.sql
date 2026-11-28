-- Story archive: indefinite owner retention, private storage access, no automated purge.

-- ---------------------------------------------------------------------------
-- Column: canonical storage object path (backfilled from legacy public URLs)
-- ---------------------------------------------------------------------------

alter table public.stories
  add column if not exists storage_path text;

comment on column public.stories.storage_path is
  'Object path in the stories bucket (no host). Authoritative for signed URL access.';

update public.stories s
set storage_path = public.story_storage_path_from_image_url(s.image_url)
where (s.storage_path is null or btrim(s.storage_path) = '')
  and s.image_url is not null
  and btrim(s.image_url) <> '';

update public.stories s
set storage_path = btrim(s.image_url)
where (s.storage_path is null or btrim(s.storage_path) = '')
  and s.image_url is not null
  and btrim(s.image_url) <> ''
  and position('http' in lower(btrim(s.image_url))) <> 1;

create index if not exists stories_user_id_created_at_desc_idx
  on public.stories (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Storage gateway: owner always; others only while story is publicly active
-- ---------------------------------------------------------------------------

create or replace function public.story_row_storage_path(p_story public.stories)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(
    nullif(btrim(p_story.storage_path), ''),
    public.story_storage_path_from_image_url(p_story.image_url)
  );
$$;

create or replace function public.story_storage_object_readable(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.stories s
    where public.story_row_storage_path(s) = p_name
      and (
        s.user_id = auth.uid()
        or (
          public.story_is_publicly_active(s.created_at)
          and (auth.uid() is null or not (s.user_id = any (public.rls_viewer_block_peer_ids())))
          and (
            exists (
              select 1
              from public.profiles p
              where p.id = s.user_id
                and coalesce(p.is_private, false) = false
            )
            or (
              auth.uid() is not null
              and exists (
                select 1
                from public.followers f
                where f.following_id = s.user_id
                  and f.follower_id = auth.uid()
              )
            )
          )
        )
      )
  );
$$;

-- Private bucket (public URLs must not remain the access path).
update storage.buckets
set public = false
where id = 'stories';

-- ---------------------------------------------------------------------------
-- Retention helpers: metadata purge disabled (owner archive is indefinite)
-- ---------------------------------------------------------------------------

create or replace function public.story_activity_retention_cutoff()
returns timestamptz
language sql
stable
set search_path = public
as $$
  select 'epoch'::timestamptz;
$$;

comment on function public.story_activity_retention_cutoff() is
  'Deprecated automatic metadata purge; stories remain until owner deletes.';

-- ---------------------------------------------------------------------------
-- Owner archived stories (expired public window, still owned)
-- ---------------------------------------------------------------------------

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
      s.created_at,
      s.text_overlays
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

-- ---------------------------------------------------------------------------
-- Single story retrieval for viewer / DM (active public OR owner archive)
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
    'created_at', v_row.created_at,
    'text_overlays', v_row.text_overlays
  );
end;
$$;

comment on function public.rpc_v1_story_for_viewer(uuid) is
  'Returns a story row when the caller may view it (24h public rules or owner archive).';

revoke all on function public.rpc_v1_story_for_viewer(uuid) from public;
grant execute on function public.rpc_v1_story_for_viewer(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- DM / reply media gate (prevents non-owners from cached preview of expired)
-- ---------------------------------------------------------------------------

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
    'created_at', v_row.created_at,
    'storage_path', public.story_row_storage_path(v_row),
    'image_url', v_row.image_url
  );
end;
$$;

comment on function public.rpc_v1_story_dm_media_access(uuid) is
  'Authorizes story media for DM previews and deep links.';

revoke all on function public.rpc_v1_story_dm_media_access(uuid) from public;
grant execute on function public.rpc_v1_story_dm_media_access(uuid) to authenticated;