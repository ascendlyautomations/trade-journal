-- Getting Started checklist: one bounded RPC replacing seven REST fan-out queries.

create or replace function public.rpc_v1_getting_started_signals()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_first_private_trade_id uuid;
  v_trade_count integer := 0;
  v_profile_post_count integer := 0;
  v_follow_count integer := 0;
  v_has_public_trade boolean := false;
  v_has_ever_joined_other_room boolean := false;
  v_onboarding_completed boolean := false;
  v_has_seen_intro boolean := false;
  v_has_seen_complete_popup boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select
    coalesce(p.onboarding_completed, false),
    coalesce(p.has_seen_getting_started_intro, false),
    coalesce(p.has_seen_onboarding_complete_popup, false)
  into
    v_onboarding_completed,
    v_has_seen_intro,
    v_has_seen_complete_popup
  from public.profiles p
  where p.id = v_uid;

  select count(*)::integer
  into v_trade_count
  from public.trades t
  where t.user_id = v_uid;

  select exists (
    select 1
    from public.trades t
    where t.user_id = v_uid
      and t.is_public is true
  )
  into v_has_public_trade;

  select t.id
  into v_first_private_trade_id
  from public.trades t
  where t.user_id = v_uid
    and coalesce(t.is_public, false) = false
    and coalesce(t.mode, '') <> 'backtest'
  order by t.created_at desc, t.id desc
  limit 1;

  select count(*)::integer
  into v_profile_post_count
  from public.profile_posts pp
  where pp.user_id = v_uid;

  select count(*)::integer
  into v_follow_count
  from public.followers f
  where f.follower_id = v_uid;

  select exists (
    select 1
    from public.room_members rm
    inner join public.rooms r on r.id = rm.room_id
    where rm.user_id = v_uid
      and r.owner_user_id <> v_uid
  )
  into v_has_ever_joined_other_room;

  return jsonb_build_object(
    'onboarding_completed', v_onboarding_completed,
    'has_seen_getting_started_intro', v_has_seen_intro,
    'has_seen_onboarding_complete_popup', v_has_seen_complete_popup,
    'trade_count', v_trade_count,
    'profile_post_count', v_profile_post_count,
    'follow_count', v_follow_count,
    'has_ever_joined_other_room', v_has_ever_joined_other_room,
    'has_public_trade', v_has_public_trade,
    'first_private_trade_id', v_first_private_trade_id
  );
end;
$$;

comment on function public.rpc_v1_getting_started_signals() is
  'Getting Started checklist signals — replaces seven REST HEAD/GET fan-out queries.';

revoke all on function public.rpc_v1_getting_started_signals() from public;
revoke all on function public.rpc_v1_getting_started_signals() from anon;
grant execute on function public.rpc_v1_getting_started_signals() to authenticated;
