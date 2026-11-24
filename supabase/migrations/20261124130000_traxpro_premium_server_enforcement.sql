-- Server-side TraxsPro gates for premium RPCs and expense / copy-trading mutations.
-- Active only when public.free_plan_limits_enforced() is true (entitlement_enforcement_enabled).

create or replace function public.traxpro_assert_feature_access(p_user_id uuid, p_feature text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_token text := upper(trim(coalesce(p_feature, 'generic')));
begin
  if p_user_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not public.free_plan_limits_enforced() then
    return;
  end if;

  if public.profile_is_pro_user(p_user_id) then
    return;
  end if;

  case v_token
    when 'PREMIUM_ANALYTICS', 'PREMIUMANALYTICS' then
      raise exception 'TRAXPRO_PREMIUM_ANALYTICS_REQUIRED'
        using hint = 'Advanced performance analytics are available with TraxPro.';
    when 'PROP_FIRM', 'PROPFIRM', 'EXPENSE_TRACKER' then
      raise exception 'TRAXPRO_PROP_FIRM_REQUIRED'
        using hint = 'Prop Firm tools are available with TraxPro.';
    when 'COPY_TRADING', 'COPYTRADING' then
      raise exception 'TRAXPRO_COPY_TRADING_REQUIRED'
        using hint = 'Copy Trading is available with TraxPro.';
    when 'BACKTEST_LAB', 'BACKTESTLAB' then
      raise exception 'TRAXPRO_BACKTEST_LAB_REQUIRED'
        using hint = 'Backtest Lab is available with TraxPro.';
    when 'TRADING_REPORTS', 'TRADINGREPORTS' then
      raise exception 'TRAXPRO_TRADING_REPORTS_REQUIRED'
        using hint = 'Trading reports are available with TraxPro.';
    else
      raise exception 'TRAXPRO_FEATURE_REQUIRED'
        using hint = 'This feature is available with TraxPro.';
  end case;
end;
$$;

comment on function public.traxpro_assert_feature_access(uuid, text) is
  'Raises when entitlement enforcement is on and the user is not TraxPro. No-op when enforcement is off.';

-- Dashboard premium chart bundles (all-accounts).
create or replace function public.rpc_v1_analytics_dashboard_aggregate_charts_v3()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_as_of date;
  v_presets text[] := array['d7', 'd30', 'd90', 'ytd', 'all'];
  v_preset text;
  v_charts jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  perform public.traxpro_assert_feature_access(v_uid, 'premium_analytics');

  v_as_of := public.analytics_dashboard_as_of_et();

  foreach v_preset in array v_presets loop
    v_charts := v_charts || jsonb_build_object(
      v_preset,
      public.analytics_dashboard_charts_bundle(v_uid, v_preset, v_as_of, null)
    );
  end loop;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'account_id', null,
      'as_of_et', v_as_of,
      'presets', v_charts
    )
  );
end;
$$;

-- Dashboard premium chart bundles (per-account).
create or replace function public.rpc_v1_analytics_dashboard_account_charts_v3(
  p_account_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_as_of date;
  v_presets text[] := array['d7', 'd30', 'd90', 'ytd', 'all'];
  v_preset text;
  v_charts jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_account_id is null then
    raise exception 'invalid_account' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.accounts a
    where a.user_id = v_uid and a.id = p_account_id
  ) then
    raise exception 'account_not_found' using errcode = '22023';
  end if;

  perform public.traxpro_assert_feature_access(v_uid, 'premium_analytics');

  v_as_of := public.analytics_dashboard_as_of_et();

  foreach v_preset in array v_presets loop
    v_charts := v_charts || jsonb_build_object(
      v_preset,
      public.analytics_dashboard_charts_bundle(v_uid, v_preset, v_as_of, p_account_id)
    );
  end loop;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'account_id', p_account_id,
      'as_of_et', v_as_of,
      'presets', v_charts
    )
  );
end;
$$;

-- Prop firm analytics bootstrap (preserve 20260915180000 contract + TraxPro gate).
create or replace function public.rpc_v1_prop_firm_bootstrap()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
  v_accounts jsonb := '[]'::jsonb;
  v_payout_cycles jsonb := '[]'::jsonb;
  v_achievements jsonb := '[]'::jsonb;
  v_trades jsonb := '[]'::jsonb;
  v_account_ids uuid[];
  v_account_ids_text text[];
  v_funded_ids uuid[];
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  perform public.traxpro_assert_feature_access(v_uid, 'prop_firm');

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'name', a.name,
          'account_size', a.account_size,
          'account_number', a.account_number,
          'mode', a.mode,
          'consistency', a.consistency,
          'max_drawdown', a.max_drawdown,
          'daily_drawdown', a.daily_drawdown,
          'drawdown_type', a.drawdown_type,
          'profit_target', a.profit_target,
          'winning_days', a.winning_days,
          'winning_day_threshold', a.winning_day_threshold,
          'payout_drawdown_behavior', a.payout_drawdown_behavior,
          'remember_payout_drawdown_behavior', a.remember_payout_drawdown_behavior
        )
        order by a.name nulls last, a.id
      ),
      '[]'::jsonb
    ),
    coalesce(array_agg(a.id), '{}'::uuid[]),
    coalesce(array_agg(a.id::text), '{}'::text[])
  into v_accounts, v_account_ids, v_account_ids_text
  from public.accounts a
  where a.user_id = v_uid
    and a.category = 'Prop Firm';

  select coalesce(array_agg(a.id), '{}'::uuid[])
  into v_funded_ids
  from public.accounts a
  where a.user_id = v_uid
    and a.category = 'Prop Firm'
    and lower(trim(coalesce(a.mode, ''))) = 'funded';

  if coalesce(array_length(v_funded_ids, 1), 0) > 0 then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', pc.id,
          'account_id', pc.account_id,
          'started_at', pc.started_at,
          'ended_at', pc.ended_at,
          'cycle_start_balance', pc.cycle_start_balance,
          'payout_amount', pc.payout_amount,
          'note', pc.note,
          'balance_before_payout', pc.balance_before_payout,
          'balance_after_payout', pc.balance_after_payout,
          'drawdown_behavior', pc.drawdown_behavior,
          'drawdown_floor_after_payout', pc.drawdown_floor_after_payout,
          'cycle_number', pc.cycle_number
        )
        order by pc.account_id, pc.started_at desc
      ),
      '[]'::jsonb
    )
    into v_payout_cycles
    from public.account_payout_cycles pc
    where pc.user_id = v_uid
      and pc.account_id = any (v_funded_ids);
  end if;

  if coalesce(array_length(v_account_ids, 1), 0) > 0 then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', ach.id,
          'user_id', ach.user_id,
          'achievement_type', ach.achievement_type,
          'title', ach.title,
          'description', ach.description,
          'badge_key', ach.badge_key,
          'tier', ach.tier,
          'category', ach.category,
          'value_numeric', ach.value_numeric,
          'value_text', ach.value_text,
          'currency', ach.currency,
          'account_type', ach.account_type,
          'account_name', ach.account_name,
          'account_size', ach.account_size,
          'account_id', ach.account_id,
          'mode', ach.mode,
          'firm', ach.firm,
          'image_url', ach.image_url,
          'achieved_at', ach.achieved_at,
          'created_at', ach.created_at,
          'updated_at', ach.updated_at,
          'is_featured', ach.is_featured,
          'is_public', ach.is_public,
          'sort_order', ach.sort_order,
          'metadata', ach.metadata
        )
        order by ach.achieved_at desc nulls last, ach.created_at desc
      ),
      '[]'::jsonb
    )
    into v_achievements
    from public.achievements ach
    where ach.user_id = v_uid
      and ach.account_id = any (v_account_ids);

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'account_id', t.account_id,
          'pnl', t.pnl,
          'date', t.date,
          'trade_date', t.trade_date,
          'entry_time', t.entry_time,
          'exit_time', t.exit_time,
          'created_at', t.created_at
        )
        order by t.trade_date asc nulls last, t.entry_time asc nulls last, t.created_at asc
      ),
      '[]'::jsonb
    )
    into v_trades
    from public.trades t
    where t.user_id = v_uid
      and nullif(trim(t.account_id), '') is not null
      and t.account_id = any (v_account_ids_text);
  end if;

  return jsonb_build_object(
    'meta',
    jsonb_build_object(
      'contract_version',
      'v1',
      'server_time',
      to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id',
      v_uid::text
    ),
    'data',
    jsonb_build_object(
      'accounts',
      v_accounts,
      'payout_cycles',
      v_payout_cycles,
      'achievements',
      v_achievements,
      'trades',
      v_trades
    )
  );
end;
$$;

revoke all on function public.rpc_v1_prop_firm_bootstrap() from public;
grant execute on function public.rpc_v1_prop_firm_bootstrap() to authenticated;

comment on function public.rpc_v1_analytics_dashboard_aggregate_charts_v3() is
  'Dashboard V3 all-accounts charts; TraxPro required when entitlement enforcement is on.';

comment on function public.rpc_v1_analytics_dashboard_account_charts_v3(uuid) is
  'Dashboard V3 per-account charts; TraxPro required when entitlement enforcement is on.';

comment on function public.rpc_v1_prop_firm_bootstrap() is
  'Prop Firm bootstrap; TraxPro required when entitlement enforcement is on.';

-- Expense tracker mutations.
create or replace function public.prop_firm_expenses_enforce_traxpro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if public.rate_limit_is_service_role() then
    return coalesce(new, old);
  end if;

  v_user_id := coalesce(new.user_id, old.user_id);
  perform public.traxpro_assert_feature_access(v_user_id, 'prop_firm');
  return coalesce(new, old);
end;
$$;

drop trigger if exists prop_firm_expenses_enforce_traxpro on public.prop_firm_expenses;
create trigger prop_firm_expenses_enforce_traxpro
  before insert or update or delete on public.prop_firm_expenses
  for each row
  execute function public.prop_firm_expenses_enforce_traxpro();

comment on function public.prop_firm_expenses_enforce_traxpro() is
  'Blocks expense tracker writes for Free users when entitlement enforcement is on.';

-- Copy trading: cover insert, update, delete on groups and membership rows.
create or replace function public.copy_trading_groups_enforce_traxpro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if public.rate_limit_is_service_role() then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    v_user_id := old.user_id;
  else
    v_user_id := new.user_id;
  end if;

  perform public.traxpro_assert_feature_access(v_user_id, 'copy_trading');
  return coalesce(new, old);
end;
$$;

drop trigger if exists copy_trading_groups_enforce_traxpro on public.copy_trading_groups;
create trigger copy_trading_groups_enforce_traxpro
  before insert or update or delete on public.copy_trading_groups
  for each row
  execute function public.copy_trading_groups_enforce_traxpro();

create or replace function public.copy_trading_group_accounts_enforce_traxpro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if public.rate_limit_is_service_role() then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    v_user_id := old.user_id;
  else
    v_user_id := new.user_id;
  end if;

  perform public.traxpro_assert_feature_access(v_user_id, 'copy_trading');
  return coalesce(new, old);
end;
$$;

drop trigger if exists copy_trading_group_accounts_enforce_traxpro on public.copy_trading_group_accounts;
create trigger copy_trading_group_accounts_enforce_traxpro
  before insert or update or delete on public.copy_trading_group_accounts
  for each row
  execute function public.copy_trading_group_accounts_enforce_traxpro();

comment on function public.copy_trading_groups_enforce_traxpro() is
  'Requires TraxPro for copy trading group mutations when entitlement enforcement is on.';

comment on function public.copy_trading_group_accounts_enforce_traxpro() is
  'Requires TraxPro for copy trading membership mutations when entitlement enforcement is on.';

create or replace function public.tracker_income_enforce_traxpro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if public.rate_limit_is_service_role() then
    return coalesce(new, old);
  end if;

  v_user_id := coalesce(new.user_id, old.user_id);
  perform public.traxpro_assert_feature_access(v_user_id, 'prop_firm');
  return coalesce(new, old);
end;
$$;

drop trigger if exists tracker_income_enforce_traxpro on public.tracker_income;
create trigger tracker_income_enforce_traxpro
  before insert or update or delete on public.tracker_income
  for each row
  execute function public.tracker_income_enforce_traxpro();

drop trigger if exists prop_firm_expense_settings_enforce_traxpro on public.prop_firm_expense_settings;
create trigger prop_firm_expense_settings_enforce_traxpro
  before insert or update or delete on public.prop_firm_expense_settings
  for each row
  execute function public.prop_firm_expenses_enforce_traxpro();