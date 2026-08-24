-- Backend V2 Phase 2: Session bootstrap (single JSON document for shared session state).
-- SECURITY INVOKER — relies on existing RLS for profiles/accounts/followers/notifications.
-- Does not alter tables. Composes reads only.

create or replace function public._v1_session_early_access_active(p profiles)
returns boolean
language sql
stable
as $$
  select
    p.early_access_status = 'active'
    and p.early_access_enrolled_at is not null
    and p.early_access_started_at is not null
    and p.early_access_campaign_id = 'traxs_pro_for_life_v1'
    and p.early_access_enrollment_source in ('standard_email', 'standard_oauth')
    and p.early_access_ends_at is not null
    and p.early_access_ends_at > now();
$$;

create or replace function public._v1_session_is_pro(p profiles)
returns boolean
language sql
stable
as $$
  select
    coalesce(p.is_pro, false)
    or coalesce(p.creator_access, false)
    or lower(trim(coalesce(p.subscription_status::text, ''))) in ('active', 'trialing')
    or public._v1_session_early_access_active(p)
    or (
      p.trial_end is not null
      and p.trial_end > now()
    );
$$;

create or replace function public.rpc_v1_session_bootstrap()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles%rowtype;
  v_is_pro boolean := false;
  v_early boolean := false;
  v_is_admin boolean := false;
  v_is_affiliate boolean := false;
  v_notif_unread integer := 0;
  v_dm_unread integer := 0;
  v_prefs_enabled boolean := true;
  v_accounts jsonb := '[]'::jsonb;
  v_following jsonb := '[]'::jsonb;
  v_prefs_defaults jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select *
  into v_profile
  from public.profiles
  where id = v_uid;

  if not found then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  v_early := public._v1_session_early_access_active(v_profile);
  v_is_pro := public._v1_session_is_pro(v_profile);

  select exists (
    select 1 from public.admin_users au where au.user_id = v_uid
  )
  into v_is_admin;

  select exists (
    select 1
    from public.affiliates a
    where a.user_id = v_uid
      and coalesce(a.is_active, false) = true
  )
  into v_is_affiliate;

  select coalesce(np.notifications_enabled, true),
         jsonb_build_object(
           'likes_enabled', coalesce(np.likes_enabled, true),
           'comments_enabled', coalesce(np.comments_enabled, true),
           'direct_messages_enabled', coalesce(np.direct_messages_enabled, true),
           'followers_enabled', coalesce(np.followers_enabled, true)
         )
  into v_prefs_enabled, v_prefs_defaults
  from public.notification_preferences np
  where np.user_id = v_uid;

  if not found then
    v_prefs_enabled := true;
    v_prefs_defaults := '{}'::jsonb;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'name', a.name,
        'type', a.mode,
        'currency', null,
        'is_active', coalesce(a.is_active, true)
      )
      order by a.created_at asc nulls last, a.id asc
    ),
    '[]'::jsonb
  )
  into v_accounts
  from public.accounts a
  where a.user_id = v_uid;

  select coalesce(
    jsonb_agg(f.following_id order by f.following_id),
    '[]'::jsonb
  )
  into v_following
  from public.followers f
  where f.follower_id = v_uid;

  select count(*)::integer
  into v_notif_unread
  from public.notifications n
  where n.user_id = v_uid
    and n.read = false
    and n.type in (
      'like',
      'comment',
      'room_join',
      'room_mention',
      'follow',
      'follow_request',
      'follow_request_accepted',
      'affiliate_referral',
      'affiliate_commission_earned',
      'trading_report'
    );

  -- Match get_app_icon_badge DM formula (unmuted conversations only).
  select coalesce(sum(c.cnt), 0)::integer
  into v_dm_unread
  from (
    select count(m.id)::integer as cnt
    from public.conversation_participants cp
    left join public.conversation_member_preferences prefs
      on prefs.user_id = cp.user_id
     and prefs.conversation_id = cp.conversation_id
    left join public.messages m
      on m.conversation_id = cp.conversation_id
     and m.sender_id is not null
     and m.sender_id <> cp.user_id
     and (
       prefs.last_read_at is null
       or m.created_at > prefs.last_read_at
     )
    where cp.user_id = v_uid
      and coalesce(prefs.notifications_enabled, true) = true
    group by cp.conversation_id
  ) c;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'viewer', jsonb_build_object(
        'id', v_profile.id,
        'username', v_profile.username,
        'display_name', v_profile.name,
        'avatar_url', v_profile.avatar_url,
        'is_private', coalesce(v_profile.is_private, false),
        'onboarding_flags', jsonb_build_object(
          'onboarding_completed', coalesce(v_profile.onboarding_completed, false),
          'has_seen_getting_started_intro', coalesce(v_profile.has_seen_getting_started_intro, false),
          'has_seen_onboarding_complete_popup', coalesce(v_profile.has_seen_onboarding_complete_popup, false)
        ),
        'entitlement', jsonb_build_object(
          'plan', case when v_is_pro then 'pro' else 'free' end,
          'status', v_profile.subscription_status,
          'flags', jsonb_build_object(
            'is_pro', coalesce(v_profile.is_pro, false),
            'creator_access', coalesce(v_profile.creator_access, false),
            'early_access_active', v_early,
            'use_free_tier', coalesce(v_profile.use_free_tier, false),
            'is_beta_tester', coalesce(v_profile.is_beta_tester, false),
            'is_admin', v_is_admin,
            'is_affiliate', v_is_affiliate
          )
        )
      ),
      'session_profile', jsonb_build_object(
        'id', v_profile.id,
        'username', v_profile.username,
        'avatar_url', v_profile.avatar_url,
        'is_pro', v_profile.is_pro,
        'creator_access', v_profile.creator_access,
        'subscription_status', v_profile.subscription_status,
        'trial_end', v_profile.trial_end,
        'stripe_customer_id', v_profile.stripe_customer_id,
        'signup_flow_source', v_profile.signup_flow_source,
        'early_access_enrolled_at', v_profile.early_access_enrolled_at,
        'early_access_started_at', v_profile.early_access_started_at,
        'early_access_ends_at', v_profile.early_access_ends_at,
        'early_access_status', v_profile.early_access_status,
        'early_access_campaign_id', v_profile.early_access_campaign_id,
        'early_access_enrollment_source', v_profile.early_access_enrollment_source,
        'lifetime_access_source', v_profile.lifetime_access_source,
        'lifetime_access_granted_at', v_profile.lifetime_access_granted_at,
        'is_banned', v_profile.is_banned,
        'banned_reason', v_profile.banned_reason,
        'referral_code', v_profile.referral_code,
        'is_beta_tester', v_profile.is_beta_tester,
        'use_free_tier', v_profile.use_free_tier,
        'onboarding_completed', v_profile.onboarding_completed,
        'has_seen_getting_started_intro', v_profile.has_seen_getting_started_intro,
        'has_seen_onboarding_complete_popup', v_profile.has_seen_onboarding_complete_popup,
        'bio', v_profile.bio,
        'trading_style', v_profile.trading_style,
        'trader_type', v_profile.trader_type,
        'primary_market', v_profile.primary_market,
        'started_trading', v_profile.started_trading,
        'max_drawdown_limit', v_profile.max_drawdown_limit,
        'is_private', v_profile.is_private,
        'has_email_password', v_profile.has_email_password
      ),
      'accounts_summary', v_accounts,
      'following_ids', v_following,
      'badges', jsonb_build_object(
        'notifications_unread', coalesce(v_notif_unread, 0),
        'dm_unread', coalesce(v_dm_unread, 0),
        'rooms_unread', null
      ),
      'prefs_min', jsonb_build_object(
        'notifications_enabled_summary', v_prefs_enabled,
        'messaging_defaults', v_prefs_defaults
      ),
      'realtime', jsonb_build_object(
        'channels', jsonb_build_array(
          'notifications',
          'messages',
          'profiles',
          'followers'
        )
      )
    )
  );
end;
$$;

comment on function public.rpc_v1_session_bootstrap() is
  'Backend V2 session bootstrap — viewer, accounts summary, following IDs, badges, prefs_min. Initial state only; Realtime owns increments.';

revoke all on function public.rpc_v1_session_bootstrap() from public;
grant execute on function public.rpc_v1_session_bootstrap() to authenticated;

revoke all on function public._v1_session_early_access_active(profiles) from public;
revoke all on function public._v1_session_is_pro(profiles) from public;
