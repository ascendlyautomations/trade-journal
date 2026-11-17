-- Owner Trades list (rpc_v1_trades_list_bootstrap_v2) — surface max_rr_reached on journal summary wire.

create or replace function public.trade_summary_owner_extension_json(
  p_trade public.trades
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_strip_nulls(
    jsonb_build_object(
      'account_id', nullif(trim(coalesce(p_trade.account_id, '')), ''),
      'account_name', nullif(trim(coalesce(p_trade.account_name, '')), ''),
      'strategy', nullif(trim(coalesce(p_trade.strategy, '')), ''),
      'entry_price', p_trade.entry_price,
      'exit_price', p_trade.exit_price,
      'session', nullif(trim(coalesce(p_trade.session, '')), ''),
      'max_rr_reached', p_trade.max_rr_reached,
      'source_account_id', nullif(trim(coalesce(p_trade.source_account_id::text, '')), ''),
      'copied_account_ids', case
        when p_trade.copied_account_ids is null or cardinality(p_trade.copied_account_ids) = 0 then null
        else to_jsonb(p_trade.copied_account_ids)
      end,
      'copy_trading_group_id', nullif(trim(coalesce(p_trade.copy_trading_group_id::text, '')), '')
    )
  );
$$;

comment on function public.trade_summary_owner_extension_json(public.trades) is
  'Owner Journal list extension — account, session, strategy, execution prices, max_rr_reached, copy-trade linkage.';