-- Story insights: display names, reply flags, and replier rows for owner analytics.

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
  v_repliers jsonb := '[]'::jsonb;
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
      p.name as display_name,
      p.avatar_url,
      sv.first_viewed_at as viewed_at,
      exists (
        select 1
        from public.story_likes sl
        where sl.story_id = p_story_id
          and sl.user_id = p.id
      ) as liked,
      exists (
        select 1
        from public.messages m
        where m.type = 'story_reply'
          and coalesce(m.deleted_for_everyone, false) = false
          and m.sender_id = p.id
          and public.story_reply_content_story_id(m.content) = p_story_id::text
          and public.story_reply_content_story_owner_id(m.content) = v_owner::text
      ) as replied
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
      p.name as display_name,
      p.avatar_url,
      sl.created_at as liked_at,
      true as liked
    from public.story_likes sl
    join public.profiles p on p.id = sl.user_id
    where sl.story_id = p_story_id
    order by sl.created_at desc
    limit 200
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.replied_at desc), '[]'::jsonb)
  into v_repliers
  from (
    select
      p.id,
      p.username,
      p.name as display_name,
      p.avatar_url,
      max(m.created_at) as replied_at,
      true as replied
    from public.messages m
    join public.profiles p on p.id = m.sender_id
    where m.type = 'story_reply'
      and coalesce(m.deleted_for_everyone, false) = false
      and public.story_reply_content_story_id(m.content) = p_story_id::text
      and public.story_reply_content_story_owner_id(m.content) = v_owner::text
    group by p.id, p.username, p.name, p.avatar_url
    order by max(m.created_at) desc
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
      'likers', v_likers,
      'repliers', v_repliers
    )
  );
end;
$$;

comment on function public.rpc_v1_story_insights(uuid) is
  'Owner-only story activity: viewer/like/reply counts and profile rows.';