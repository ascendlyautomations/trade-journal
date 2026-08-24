-- Phase H1: Prop Firm Analytics bootstrap — one bounded JSON replacing per-account payout fan-out.
-- SECURITY INVOKER: RLS on accounts, trades, achievements, account_payout_cycles applies.

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
  v_funded_ids uuid[];
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

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
    coalesce(array_agg(a.id), '{}'::uuid[])
  into v_accounts, v_account_ids
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
      and t.account_id = any (v_account_ids);
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
