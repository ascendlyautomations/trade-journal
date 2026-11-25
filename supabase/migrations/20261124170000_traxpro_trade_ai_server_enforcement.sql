-- Trade AI (Trade Analyst) server enforcement when entitlement limits are on.
-- Complements BFF /api/analyze-trade (requireAIFeatureEntitlement + rate limits).
--
-- Production storage today: public.trades.ai_feedback (web analyst + BFF persist).
-- public.trade_ai_messages is optional (migration 20260813010000); attach gate only if present.

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
    when 'AI_ANALYST', 'AIANALYST', 'TRADE_AI', 'TRADEAI' then
      raise exception 'TRAXPRO_AI_ANALYST_REQUIRED'
        using hint = 'AI Trade Analyst is available with TraxPro.';
    else
      raise exception 'TRAXPRO_FEATURE_REQUIRED'
        using hint = 'This feature is available with TraxPro.';
  end case;
end;
$$;

comment on function public.traxpro_assert_feature_access(uuid, text) is
  'Raises when entitlement enforcement is on and the user is not TraxPro. No-op when enforcement is off.';

-- Optional native multi-turn history (only when trade_ai_messages exists).
create or replace function public.trade_ai_messages_enforce_traxpro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  perform public.traxpro_assert_feature_access(new.user_id, 'ai_analyst');
  return new;
end;
$$;

comment on function public.trade_ai_messages_enforce_traxpro() is
  'Requires TraxPro to append Trade AI messages when entitlement enforcement is on.';

do $apply$
begin
  if to_regclass('public.trade_ai_messages') is not null then
    execute $trg$
      drop trigger if exists trade_ai_messages_enforce_traxpro on public.trade_ai_messages;
      create trigger trade_ai_messages_enforce_traxpro
        before insert on public.trade_ai_messages
        for each row
        execute function public.trade_ai_messages_enforce_traxpro();
    $trg$;
  end if;
end $apply$;

-- trades.ai_feedback: web analyst cache + any client PostgREST writes (BFF uses service role).
create or replace function public.trades_enforce_ai_feedback_traxpro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.ai_feedback is not null and btrim(new.ai_feedback) <> '' then
      perform public.traxpro_assert_feature_access(new.user_id, 'ai_analyst');
    end if;
    return new;
  end if;

  if new.ai_feedback is distinct from old.ai_feedback then
    perform public.traxpro_assert_feature_access(new.user_id, 'ai_analyst');
  end if;

  return new;
end;
$$;

comment on function public.trades_enforce_ai_feedback_traxpro() is
  'Blocks client writes to trades.ai_feedback for Free users when entitlement enforcement is on.';

do $apply$
begin
  if exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'trades'
      and c.column_name = 'ai_feedback'
  ) then
    execute $trg$
      drop trigger if exists trades_enforce_ai_feedback_traxpro on public.trades;
      create trigger trades_enforce_ai_feedback_traxpro
        before insert or update of ai_feedback on public.trades
        for each row
        execute function public.trades_enforce_ai_feedback_traxpro();
    $trg$;
  end if;
end $apply$;