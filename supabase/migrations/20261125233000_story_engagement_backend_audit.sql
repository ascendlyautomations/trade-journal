-- Story engagement audit delta (apply after 20261125130000_story_engagement.sql).
-- Additive only: analytics reply totals, safer JSON parsing, reply lookup index, story_likes Realtime.
-- Safe to run in Supabase SQL Editor when 20261125130000 is already applied.

-- -----------------------------------------------------------------------------
-- Helpers: story-reply DM JSON (matches lib/storyReplyMessage.ts + iOS StoryReplyMessageSupport)
-- -----------------------------------------------------------------------------

create or replace function public.story_reply_content_story_id(p_content text)
returns text
language plpgsql
immutable
parallel safe
set search_path = public
as $$
begin
  if p_content is null or btrim(p_content) = '' then
    return null;
  end if;
  if left(btrim(p_content), 1) <> '{' then
    return null;
  end if;
  return nullif(btrim((p_content::jsonb ->> 'story_id')), '');
exception
  when others then
    return null;
end;
$$;

comment on function public.story_reply_content_story_id(text) is
  'Extracts story_id from story_reply message JSON; returns null on invalid content.';

create or replace function public.story_reply_content_story_owner_id(p_content text)
returns text
language plpgsql
immutable
parallel safe
set search_path = public
as $$
begin
  if p_content is null or btrim(p_content) = '' then
    return null;
  end if;
  if left(btrim(p_content), 1) <> '{' then
    return null;
  end if;
  return nullif(btrim((p_content::jsonb ->> 'story_owner_id')), '');
exception
  when others then
    return null;
end;
$$;

comment on function public.story_reply_content_story_owner_id(text) is
  'Extracts story_owner_id from story_reply message JSON; returns null on invalid content.';

revoke all on function public.story_reply_content_story_id(text) from public;
grant execute on function public.story_reply_content_story_id(text) to authenticated;

revoke all on function public.story_reply_content_story_owner_id(text) from public;
grant execute on function public.story_reply_content_story_owner_id(text) to authenticated;

-- -----------------------------------------------------------------------------
-- Analytics: index story-reply messages by story + owner (owner-only insights RPC)
-- -----------------------------------------------------------------------------

create index if not exists messages_story_reply_insights_idx
  on public.messages (
    public.story_reply_content_story_id(content),
    public.story_reply_content_story_owner_id(content)
  )
  where type = 'story_reply'
    and coalesce(deleted_for_everyone, false) = false
    and public.story_reply_content_story_id(content) is not null;

-- -----------------------------------------------------------------------------
-- Owner insights (iOS Story Analytics sheet + future web parity)
-- -----------------------------------------------------------------------------

create or replace function public.rpc_v1_story_insights(p_story_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_view_count integer := 0;
  v_like_count integer := 0;
  v_reply_count integer := 0;
  v_viewers jsonb := '[]'::jsonb;
  v_likers jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select s.user_id into v_owner
  from public.stories s
  where s.id = p_story_id;

  if v_owner is null then
    raise exception 'story_not_found' using errcode = 'P0002';
  end if;

  if v_owner <> auth.uid() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select count(*)::integer into v_view_count
  from public.story_views sv
  where sv.story_id = p_story_id;

  select count(*)::integer into v_like_count
  from public.story_likes sl
  where sl.story_id = p_story_id;

  select count(*)::integer into v_reply_count
  from public.messages m
  where m.type = 'story_reply'
    and coalesce(m.deleted_for_everyone, false) = false
    and public.story_reply_content_story_id(m.content) = p_story_id::text
    and public.story_reply_content_story_owner_id(m.content) = v_owner::text;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.viewed_at desc), '[]'::jsonb)
  into v_viewers
  from (
    select
      p.id,
      p.username,
      p.avatar_url,
      sv.first_viewed_at as viewed_at,
      exists (
        select 1
        from public.story_likes sl
        where sl.story_id = p_story_id
          and sl.user_id = p.id
      ) as liked
    from public.story_views sv
    join public.profiles p on p.id = sv.viewer_id
    where sv.story_id = p_story_id
    order by sv.first_viewed_at desc
    limit 200
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.liked_at desc), '[]'::jsonb)
  into v_likers
  from (
    select
      p.id,
      p.username,
      p.avatar_url,
      sl.created_at as liked_at,
      true as liked
    from public.story_likes sl
    join public.profiles p on p.id = sl.user_id
    where sl.story_id = p_story_id
    order by sl.created_at desc
    limit 200
  ) t;

  return jsonb_build_object(
    'meta', jsonb_build_object('contract_version', 'v1'),
    'data', jsonb_build_object(
      'story_id', p_story_id,
      'view_count', v_view_count,
      'like_count', v_like_count,
      'reply_count', v_reply_count,
      'viewers', v_viewers,
      'likers', v_likers
    )
  );
end;
$$;

comment on function public.rpc_v1_story_insights(uuid) is
  'Owner-only story activity: viewer/like/reply counts and profile rows.';

revoke all on function public.rpc_v1_story_insights(uuid) from public;
grant execute on function public.rpc_v1_story_insights(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Realtime: iOS ContentLikeTable.storyLikes (cross-device liked-state sync)
-- -----------------------------------------------------------------------------

alter table public.story_likes replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'story_likes'
    ) then
      alter publication supabase_realtime add table public.story_likes;
    end if;
  end if;
exception
  when duplicate_object then null;
end $$;