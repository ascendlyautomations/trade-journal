-- Per-viewer story seen flags for feed/profile bootstrap and viewer carousel hydration.
-- Complements story_views + rpc_v1_story_record_view (durable across sessions/devices).
--
-- Feed RPC discovery (do not match pg_get_function_identity_arguments by hand):
--   rpc_v1_feed_bootstrap — 4 args (p_scope, p_content_filter, p_limit, p_cursor)
--   rpc_v2_feed_bootstrap — 7 args (…, p_session_seed, p_rank_frozen_at, p_scan_cursor)
--     NOT p_feed_rank / p_rank_cursor / p_rank_seed (wrong names break oid lookup).
-- V2 is optional when rotating rank was never installed; V1 + profile are required.

begin;

create or replace function public.viewer_has_seen_story(p_story_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null then false
    else exists (
      select 1
      from public.story_views sv
      where sv.story_id = p_story_id
        and sv.viewer_id = auth.uid()
    )
  end;
$$;

comment on function public.viewer_has_seen_story(uuid) is
  'True when auth.uid() has a row in story_views for the story (bootstrap preview flags).';

revoke all on function public.viewer_has_seen_story(uuid) from public;
grant execute on function public.viewer_has_seen_story(uuid) to authenticated, anon;

create or replace function public.rpc_v1_viewer_active_stories()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_following uuid[];
  v_result jsonb;
begin
  if v_uid is null then
    return '[]'::jsonb;
  end if;

  select coalesce(array_agg(f.following_id), '{}'::uuid[])
  into v_following
  from public.followers f
  where f.follower_id = v_uid;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'user_id', s.user_id,
        'image_url', coalesce(s.image_url, ''),
        'storage_path', s.storage_path,
        'created_at', to_char(timezone('utc', s.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'viewer_has_seen', public.viewer_has_seen_story(s.id)
      )
      order by s.created_at desc
    ),
    '[]'::jsonb
  )
  into v_result
  from public.stories s
  where s.created_at > (timezone('utc', now()) - interval '24 hours')
    and s.user_id = any (array_append(v_following, v_uid))
    and (
      s.user_id = v_uid
      or not public.users_have_active_block(v_uid, s.user_id)
    );

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

comment on function public.rpc_v1_viewer_active_stories() is
  'Active stories for the viewer following graph with per-story viewer_has_seen flags.';

revoke all on function public.rpc_v1_viewer_active_stories() from public;
grant execute on function public.rpc_v1_viewer_active_stories() to authenticated;

-- Idempotent pg_get_functiondef patch (feed stories_json + profile active_stories).
create or replace function public._patch_bootstrap_story_viewer_has_seen(p_oid oid)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  src text;
  updated text;
  feed_updated text;
  profile_updated text;
  proc regprocedure;
begin
  select pg_get_functiondef(p_oid) into src;
  if src is null then
    return false;
  end if;

  if position('viewer_has_seen_story(s.id)' in src) > 0 then
    return true;
  end if;

  proc := p_oid::regprocedure;

  feed_updated := replace(
    src,
    $feed_old$
          'created_at', to_char(timezone('utc', s.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        )
        order by s.created_at desc
      ),
      '[]'::jsonb
    ) as arr
    from story_rows s
$feed_old$,
    $feed_new$
          'created_at', to_char(timezone('utc', s.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'viewer_has_seen', public.viewer_has_seen_story(s.id)
        )
        order by s.created_at desc
      ),
      '[]'::jsonb
    ) as arr
    from story_rows s
$feed_new$
  );

  if feed_updated <> src then
    if position('security definer' in lower(feed_updated)) > 0 then
      raise exception '% must remain security invoker after stories_json patch', proc;
    end if;
    execute feed_updated;
    return true;
  end if;

  profile_updated := replace(
    src,
    $prof_old$
        jsonb_build_object(
          'id', s.id, 'user_id', s.user_id,
          'image_url', s.image_url, 'created_at', s.created_at
        )
$prof_old$,
    $prof_new$
        jsonb_build_object(
          'id', s.id,
          'user_id', s.user_id,
          'image_url', s.image_url,
          'created_at', s.created_at,
          'viewer_has_seen', public.viewer_has_seen_story(s.id)
        )
$prof_new$
  );

  if profile_updated <> src then
    execute profile_updated;
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public._patch_bootstrap_story_viewer_has_seen(oid) from public;

do $apply$
declare
  r record;
  ok boolean;
  v1_patched int := 0;
  v2_patched int := 0;
  prof_patched int := 0;
begin
  for r in
    select p.oid, pg_get_function_identity_arguments(p.oid) as id_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_v1_feed_bootstrap'
      and p.pronargs = 4
  loop
    ok := public._patch_bootstrap_story_viewer_has_seen(r.oid);
    if not ok then
      raise exception
        'rpc_v1_feed_bootstrap stories_json anchor not found (args: %)',
        r.id_args;
    end if;
    v1_patched := v1_patched + 1;
  end loop;

  if v1_patched = 0 then
    raise exception 'rpc_v1_feed_bootstrap (4-arg) not found';
  end if;

  for r in
    select p.oid, pg_get_function_identity_arguments(p.oid) as id_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_v2_feed_bootstrap'
      and p.pronargs = 7
  loop
    ok := public._patch_bootstrap_story_viewer_has_seen(r.oid);
    if not ok then
      raise exception
        'rpc_v2_feed_bootstrap stories_json anchor not found (args: %)',
        r.id_args;
    end if;
    v2_patched := v2_patched + 1;
  end loop;

  if v2_patched = 0 then
    raise notice
      'rpc_v2_feed_bootstrap (7-arg) not installed — skipped (rotating feed optional)';
  end if;

  for r in
    select p.oid, pg_get_function_identity_arguments(p.oid) as id_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_v1_profile_bootstrap'
      and p.pronargs = 4
  loop
    ok := public._patch_bootstrap_story_viewer_has_seen(r.oid);
    if not ok then
      raise exception
        'rpc_v1_profile_bootstrap active_stories anchor not found (args: %)',
        r.id_args;
    end if;
    prof_patched := prof_patched + 1;
  end loop;

  if prof_patched = 0 then
    raise exception 'rpc_v1_profile_bootstrap (4-arg) not found';
  end if;
end;
$apply$;

commit;