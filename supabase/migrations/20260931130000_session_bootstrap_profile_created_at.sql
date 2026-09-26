-- Expose the existing profiles.created_at on session bootstrap.
-- No new column. Older clients ignore the extra jsonb key.

create or replace function public.rpc_v1_session_bootstrap()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'viewer', jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'display_name', p.name,
        'avatar_url', p.avatar_url,
        'is_private', coalesce(p.is_private, false),
        'onboarding_flags', jsonb_build_object(
          'onboarding_completed', coalesce(p.onboarding_completed, false),
          'has_seen_getting_started_intro', coalesce(p.has_seen_getting_started_intro, false),
          'has_seen_onboarding_complete_popup', coalesce(p.has_seen_onboarding_complete_popup, false)
        ),
        'entitlement', jsonb_build_object(
          'plan', case when public._v1_session_is_pro(p) then 'pro' else 'free' end,
          'status', p.subscription_status,
          'flags', jsonb_build_object(
            'is_pro', coalesce(p.is_pro, false),
            'creator_access', coalesce(p.creator_access, false),
            'early_access_active', public._v1_session_early_access_active(p),
            'use_free_tier', coalesce(p.use_free_tier, false),
            'is_beta_tester', coalesce(p.is_beta_tester, false),
            'is_admin', ent.is_admin,
            'is_affiliate', ent.is_affiliate
          )
        )
      ),
      'session_profile', jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'avatar_url', p.avatar_url,
        'is_pro', p.is_pro,
        'creator_access', p.creator_access,
        'subscription_status', p.subscription_status,
        'trial_end', p.trial_end,
        'stripe_customer_id', p.stripe_customer_id,
        'signup_flow_source', p.signup_flow_source,
        'early_access_enrolled_at', p.early_access_enrolled_at,
        'early_access_started_at', p.early_access_started_at,
        'early_access_ends_at', p.early_access_ends_at,
        'early_access_status', p.early_access_status,
        'early_access_campaign_id', p.early_access_campaign_id,
        'early_access_enrollment_source', p.early_access_enrollment_source,
        'lifetime_access_source', p.lifetime_access_source,
        'lifetime_access_granted_at', p.lifetime_access_granted_at,
        'is_banned', p.is_banned,
        'banned_reason', p.banned_reason,
        'referral_code', p.referral_code,
        'is_beta_tester', p.is_beta_tester,
        'use_free_tier', p.use_free_tier,
        'onboarding_completed', p.onboarding_completed,
        'has_seen_getting_started_intro', p.has_seen_getting_started_intro,
        'has_seen_onboarding_complete_popup', p.has_seen_onboarding_complete_popup,
        'bio', p.bio,
        'trading_style', p.trading_style,
        'trader_type', p.trader_type,
        'primary_market', p.primary_market,
        'started_trading', p.started_trading,
        'max_drawdown_limit', p.max_drawdown_limit,
        'is_private', p.is_private,
        'has_email_password', p.has_email_password,
        'created_at', to_char(timezone('utc', p.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      ),
      'accounts_summary', coalesce(acct.summary, '[]'::jsonb),
      'following_ids', coalesce(fol.ids, '[]'::jsonb),
      'badges', jsonb_build_object(
        'notifications_unread', coalesce(social.unread, 0),
        'dm_unread', coalesce(dm.unread, 0),
        'rooms_unread', null
      ),
      'prefs_min', jsonb_build_object(
        'notifications_enabled_summary', coalesce(np.notifications_enabled, true),
        'messaging_defaults', coalesce(np.defaults, '{}'::jsonb)
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
  )
  into v_result
  from public.profiles p
  cross join lateral (
    select
      exists (
        select 1 from public.admin_users au where au.user_id = v_uid
      ) as is_admin,
      exists (
        select 1
        from public.affiliates a
        where a.user_id = v_uid
          and coalesce(a.is_active, false) = true
      ) as is_affiliate
  ) ent
  left join lateral (
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
    ) as summary
    from public.accounts a
    where a.user_id = v_uid
  ) acct on true
  left join lateral (
    select coalesce(
      jsonb_agg(f.following_id order by f.following_id),
      '[]'::jsonb
    ) as ids
    from public.followers f
    where f.follower_id = v_uid
  ) fol on true
  left join lateral (
    select count(*)::integer as unread
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
      )
  ) social on true
  left join lateral (
    select coalesce(sum(unread.cnt), 0)::integer as unread
    from public.conversation_participants cp
    left join public.conversation_member_preferences prefs
      on prefs.user_id = cp.user_id
     and prefs.conversation_id = cp.conversation_id
    cross join lateral (
      select count(m.id)::integer as cnt
      from public.messages m
      where m.conversation_id = cp.conversation_id
        and m.sender_id is not null
        and m.sender_id <> cp.user_id
        and (
          prefs.last_read_at is null
          or m.created_at > prefs.last_read_at
        )
    ) unread
    where cp.user_id = v_uid
      and coalesce(prefs.notifications_enabled, true) = true
  ) dm on true
  left join lateral (
    select
      np.notifications_enabled,
      jsonb_build_object(
        'likes_enabled', coalesce(np.likes_enabled, true),
        'comments_enabled', coalesce(np.comments_enabled, true),
        'direct_messages_enabled', coalesce(np.direct_messages_enabled, true),
        'followers_enabled', coalesce(np.followers_enabled, true)
      ) as defaults
    from public.notification_preferences np
    where np.user_id = v_uid
  ) np on true
  where p.id = v_uid;

  if v_result is null then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

comment on function public.rpc_v1_session_bootstrap() is
  'Backend V2 session bootstrap — viewer, profile created_at, accounts summary, following IDs, badges, prefs_min.';

revoke all on function public.rpc_v1_session_bootstrap() from public;
grant execute on function public.rpc_v1_session_bootstrap() to authenticated;
