-- Phase A: Optimize Session + Dashboard bootstrap RPC execution.
-- SECURITY INVOKER preserved. Response contracts unchanged.
-- Rollback: see docs/backend-v2/PHASE_A_RPC_OPTIMIZATION.md § Rollback

-- Supports accounts aggregation ORDER BY created_at, id in both bootstraps.
create index if not exists accounts_user_id_created_at_idx
  on public.accounts (user_id, created_at asc nulls last, id asc);

-- —— Session: single-row plan with LATERAL sections (replaces ~8 sequential round trips) ——

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
        'has_email_password', p.has_email_password
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
  'Backend V2 session bootstrap — viewer, accounts summary, following IDs, badges, prefs_min. Phase A optimized plan.';

revoke all on function public.rpc_v1_session_bootstrap() from public;
grant execute on function public.rpc_v1_session_bootstrap() to authenticated;

-- —— Dashboard: materialized trade CTE + single assembly (replaces ~4 trade scans) ——

create or replace function public.rpc_v1_dashboard_bootstrap(
  p_account_id uuid default null,
  p_trade_limit integer default 500
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_limit integer := greatest(1, least(coalesce(p_trade_limit, 500), 2000));
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  with ctx as (
    select v_uid as uid, v_limit as lim, p_account_id as account_id
  ),
  scoped_trades as materialized (
    select t.*
    from public.trades t
    cross join ctx
    where t.user_id = ctx.uid
      and (ctx.account_id is null or t.account_id = ctx.account_id::text)
  ),
  live_trades as materialized (
    select st.*
    from scoped_trades st
    where lower(trim(coalesce(st.mode, ''))) is distinct from 'backtest'
      and lower(trim(coalesce(st.account_type, ''))) is distinct from 'backtest'
  ),
  trade_stats as (
    select
      count(*)::integer as total_count,
      min(st.created_at) as oldest_created
    from scoped_trades st
  ),
  trade_window_json as (
    select coalesce(jsonb_agg(row_to_json(w)::jsonb), '[]'::jsonb) as trades
    from (
      select
        st.id,
        st.date,
        st.direction,
        st.pnl,
        st.notes,
        st.created_at,
        st.image_url,
        st.ticker,
        st.rr,
        st.points,
        st.session,
        st.account_type,
        st.account_id,
        st.user_id,
        st.account_size,
        st.entry_price,
        st.exit_price,
        st.entry_time,
        st.exit_time,
        st.contracts,
        st.reviewed,
        st.confidence,
        st.emotion,
        st.followed_plan,
        st.mistake_type,
        st.market_condition,
        st.news_event,
        st.timeframe,
        st.psychology_notes,
        st.trade_type,
        st.public_description,
        st.is_pinned,
        st.account_name,
        st.mode,
        st.strategy,
        st.duration_seconds,
        st.duration_text,
        st.is_public,
        st.account_category,
        st.top_confluences,
        st.trade_date,
        st.is_initial_import,
        st.copy_trading_group_id,
        st.trade_mode,
        st.source_account_id,
        st.copied_account_ids
      from scoped_trades st
      order by st.created_at desc nulls last, st.id desc
      limit (select lim from ctx)
    ) w
  ),
  metrics_json as (
    select jsonb_build_object(
      'total_trades', count(*)::integer,
      'wins', count(*) filter (where coalesce(lt.pnl, 0) > 0)::integer,
      'losses', count(*) filter (where coalesce(lt.pnl, 0) < 0)::integer,
      'win_rate', case
        when count(*) = 0 then null
        else round(
          (count(*) filter (where coalesce(lt.pnl, 0) > 0))::numeric
          / count(*)::numeric,
          6
        )
      end,
      'net_pnl', coalesce(sum(lt.pnl), 0),
      'avg_rr', avg(lt.rr),
      'avg_win', avg(lt.pnl) filter (where coalesce(lt.pnl, 0) > 0),
      'avg_loss', avg(lt.pnl) filter (where coalesce(lt.pnl, 0) < 0),
      'biggest_win', max(lt.pnl),
      'biggest_loss', min(lt.pnl)
    ) as metrics
    from live_trades lt
  ),
  equity_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('t', x.ts, 'v', x.equity)
        order by x.rn
      ),
      '[]'::jsonb
    ) as equity
    from (
      select s.rn, s.ts, s.equity
      from (
        select
          row_number() over (order by lt.created_at asc nulls last, lt.id asc) as rn,
          count(*) over () as cnt,
          to_char(lt.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as ts,
          sum(coalesce(lt.pnl, 0)) over (
            order by lt.created_at asc nulls last, lt.id asc
            rows between unbounded preceding and current row
          ) as equity
        from live_trades lt
      ) s
      where s.rn = 1
         or s.rn = s.cnt
         or s.rn % greatest(1, ceil(s.cnt::numeric / 366.0)::integer) = 0
    ) x
  ),
  accounts_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'account_number', a.account_number,
          'name', a.name,
          'account_size', a.account_size,
          'mode', a.mode,
          'category', a.category,
          'is_active', coalesce(a.is_active, true),
          'can_add_trades', a.can_add_trades,
          'note', a.note,
          'consistency', a.consistency,
          'max_drawdown', a.max_drawdown,
          'daily_drawdown', a.daily_drawdown,
          'profit_target', a.profit_target,
          'winning_days', a.winning_days,
          'winning_day_threshold', a.winning_day_threshold
        )
        order by a.created_at asc nulls last, a.id asc
      ),
      '[]'::jsonb
    ) as accounts
    from public.accounts a
    cross join ctx
    where a.user_id = ctx.uid
      and (ctx.account_id is null or a.id = ctx.account_id)
  ),
  payout_json as (
    select coalesce(sum(p.payout_amount), 0) as payout_total
    from public.account_payout_cycles p
    cross join ctx
    where p.user_id = ctx.uid
      and (ctx.account_id is null or p.account_id = ctx.account_id)
  ),
  recent_json as (
    select coalesce(jsonb_agg(elem), '[]'::jsonb) as recent
    from (
      select elem
      from trade_window_json tw,
        jsonb_array_elements(tw.trades) with ordinality as t(elem, ord)
      where ord <= 5
    ) s
  )
  select jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'accounts', aj.accounts,
      'trade_window', tw.trades,
      'trade_window_meta', jsonb_build_object(
        'limit', v_limit,
        'returned', jsonb_array_length(tw.trades),
        'history_complete',
          (ts.total_count <= jsonb_array_length(tw.trades))
          or (jsonb_array_length(tw.trades) < v_limit),
        'total_trade_count', ts.total_count,
        'oldest_created_at', case
          when ts.oldest_created is null then null
          else to_char(ts.oldest_created, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        end,
        'next_cursor', null
      ),
      'metrics', mj.metrics,
      'equity_points', ej.equity,
      'payout_total', pj.payout_total,
      'recent_trades', rj.recent
    )
  )
  into v_result
  from ctx
  cross join trade_stats ts
  cross join trade_window_json tw
  cross join metrics_json mj
  cross join equity_json ej
  cross join accounts_json aj
  cross join payout_json pj
  cross join recent_json rj;

  return v_result;
end;
$$;

comment on function public.rpc_v1_dashboard_bootstrap(uuid, integer) is
  'Backend V2 Dashboard bootstrap — accounts + trade window + metrics/equity. Phase A optimized plan.';

revoke all on function public.rpc_v1_dashboard_bootstrap(uuid, integer) from public;
grant execute on function public.rpc_v1_dashboard_bootstrap(uuid, integer) to authenticated;
