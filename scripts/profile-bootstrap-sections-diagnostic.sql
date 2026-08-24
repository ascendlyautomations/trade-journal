-- Local/staging only: section-level Profile bootstrap timing harness.
-- Run as authenticated user (set JWT claim sub) — NOT deployed via migrations.
--
-- Example:
--   SET request.jwt.claim.sub = '<viewer-uuid>';
--   SELECT public.profile_bootstrap_sections_diagnostic('nrltrades', 'trades', 6, NULL);

create or replace function public.profile_bootstrap_sections_diagnostic(
  p_identifier text,
  p_initial_tab text default 'trades',
  p_limit integer default 6,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_viewer uuid := auth.uid();
  v_profile_id uuid;
  v_profile public.profiles%rowtype;
  v_limit integer := least(greatest(coalesce(p_limit, 6), 1), 24);
  v_tab text := lower(trim(coalesce(p_initial_tab, 'trades')));
  v_is_own boolean := false;
  v_is_following boolean := false;
  v_is_requested boolean := false;
  v_follows_you boolean := false;
  v_can_view boolean := false;
  v_followers_count integer := 0;
  v_following_count integer := 0;
  v_trades jsonb := '[]'::jsonb;
  v_engagement jsonb := '{}'::jsonb;
  t0 timestamptz := clock_timestamp();
  t1 timestamptz;
  sections jsonb := '{}'::jsonb;
  r record;
begin
  if p_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into v_profile from public.profiles p where p.id = p_identifier::uuid;
  else
    select * into v_profile from public.profiles p
    where lower(p.username) = lower(trim(p_identifier));
  end if;
  t1 := clock_timestamp();
  sections := sections || jsonb_build_object(
    'profile_resolution_ms', extract(epoch from (t1 - t0)) * 1000
  );

  if v_profile.id is null then
    return jsonb_build_object('found', false, 'sections_ms', sections);
  end if;

  v_profile_id := v_profile.id;
  v_is_own := v_viewer is not null and v_viewer = v_profile_id;
  t0 := clock_timestamp();

  if v_viewer is not null and not v_is_own then
    select exists (
      select 1 from public.followers f
      where f.follower_id = v_viewer and f.following_id = v_profile_id
    ) into v_is_following;
    select exists (
      select 1 from public.follow_requests fr
      where fr.requester_id = v_viewer and fr.target_id = v_profile_id and fr.status = 'pending'
    ) into v_is_requested;
    select exists (
      select 1 from public.followers f
      where f.follower_id = v_profile_id and f.following_id = v_viewer
    ) into v_follows_you;
  end if;
  t1 := clock_timestamp();
  sections := sections || jsonb_build_object(
    'follow_relationship_ms', extract(epoch from (t1 - t0)) * 1000
  );

  v_can_view := v_is_own or coalesce(v_profile.is_private, false) = false or v_is_following;
  t0 := clock_timestamp();

  select count(*)::integer into v_followers_count
  from public.followers f where f.following_id = v_profile_id;
  select count(*)::integer into v_following_count
  from public.followers f where f.follower_id = v_profile_id;
  t1 := clock_timestamp();
  sections := sections || jsonb_build_object(
    'follow_counts_ms', extract(epoch from (t1 - t0)) * 1000
  );

  t0 := clock_timestamp();
  perform jsonb_build_object(
    'has_room', exists (select 1 from public.rooms r where r.owner_user_id = v_profile_id),
    'has_active_story', exists (
      select 1 from public.stories s
      where s.user_id = v_profile_id
        and s.created_at > (timezone('utc', now()) - interval '24 hours')
    ),
    'public_trades', case when v_can_view then (
      select count(*)::integer from public.trades t
      where t.user_id = v_profile_id and t.is_public is true
    ) else null end
  );
  t1 := clock_timestamp();
  sections := sections || jsonb_build_object(
    'section_counts_ms', extract(epoch from (t1 - t0)) * 1000
  );

  t0 := clock_timestamp();
  if v_can_view then
    perform count(*) from public.trades t
    where t.user_id = v_profile_id and t.is_public is true
      and coalesce(t.mode, '') <> 'backtest'
      and coalesce(t.account_type, '') <> 'backtest';
  end if;
  t1 := clock_timestamp();
  sections := sections || jsonb_build_object(
    'public_stats_ms', extract(epoch from (t1 - t0)) * 1000
  );

  t0 := clock_timestamp();
  if v_can_view and v_tab = 'trades' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc, t.id desc), '[]'::jsonb)
    into v_trades
    from (
      select * from public.trades t
      where t.user_id = v_profile_id and t.is_public is true
      order by t.created_at desc, t.id desc
      limit v_limit
    ) t;
  end if;
  t1 := clock_timestamp();
  sections := sections || jsonb_build_object(
    'initial_trades_page_ms', extract(epoch from (t1 - t0)) * 1000,
    'trades_returned', coalesce(jsonb_array_length(v_trades), 0)
  );

  t0 := clock_timestamp();
  if v_can_view and jsonb_array_length(v_trades) > 0 then
    with trade_ids as (
      select (elem->>'id')::uuid as id from jsonb_array_elements(v_trades) elem
    )
    select coalesce(jsonb_object_agg(ti.id::text, jsonb_build_object(
      'like_count', coalesce(lc.c, 0),
      'comment_count', coalesce(cc.c, 0)
    )), '{}'::jsonb)
    into v_engagement
    from trade_ids ti
    left join lateral (
      select count(*)::integer as c from public.trade_likes tl where tl.trade_id = ti.id
    ) lc on true
    left join lateral (
      select count(*)::integer as c from public.trade_comments tc where tc.trade_id = ti.id
    ) cc on true;
  end if;
  t1 := clock_timestamp();
  sections := sections || jsonb_build_object(
    'likes_comments_ms', extract(epoch from (t1 - t0)) * 1000
  );

  return jsonb_build_object(
    'found', true,
    'profile_id', v_profile_id,
    'can_view_trades', v_can_view,
    'sections_ms', sections
  );
end;
$$;

-- Drop after diagnostics:
-- DROP FUNCTION IF EXISTS public.profile_bootstrap_sections_diagnostic(text, text, integer, text);
