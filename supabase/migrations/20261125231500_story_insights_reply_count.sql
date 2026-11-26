-- Owner story insights: reply totals + per-viewer liked flag (native analytics sheet).

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
    and coalesce(m.content::jsonb ->> 'story_id', '') = p_story_id::text
    and coalesce(m.content::jsonb ->> 'story_owner_id', '') = v_owner::text;

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