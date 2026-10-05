-- Profile copy linkage — per-row participating account mode for public mode summary.
-- Order: helper first, then copy_linkage_json (CREATE OR REPLACE validates references at parse time).

create or replace function public.trade_summary_profile_participating_account_mode(
  p_trade public.trades
)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.profile_statistics_resolve_account_mode(
    (
      select acc.mode
      from public.accounts acc
      where acc.id = public.analytics_trade_account_uuid(p_trade.account_id)
        and acc.user_id is not distinct from p_trade.user_id
      limit 1
    ),
    p_trade.account_type,
    p_trade.mode
  );
$$;

comment on function public.trade_summary_profile_participating_account_mode(public.trades) is
  'Copy-trade Profile row — authoritative account mode for one participating account (accounts.mode preferred). SECURITY DEFINER; scoped to trade owner account id only.';

revoke all on function public.trade_summary_profile_participating_account_mode(public.trades) from public;
grant execute on function public.trade_summary_profile_participating_account_mode(public.trades) to authenticated;
grant execute on function public.trade_summary_profile_participating_account_mode(public.trades) to anon;

create or replace function public.trade_summary_profile_copy_linkage_json(
  p_trade public.trades
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select case
    when lower(trim(coalesce(p_trade.trade_mode, ''))) <> 'copy_traded' then '{}'::jsonb
    else jsonb_strip_nulls(
      jsonb_build_object(
        'account_id', nullif(trim(coalesce(p_trade.account_id, '')), ''),
        'source_account_id', nullif(trim(coalesce(p_trade.source_account_id::text, '')), ''),
        'copied_account_ids', case
          when p_trade.copied_account_ids is null or cardinality(p_trade.copied_account_ids) = 0 then null
          else to_jsonb(p_trade.copied_account_ids)
        end,
        'copy_trading_group_id', nullif(trim(coalesce(p_trade.copy_trading_group_id::text, '')), ''),
        'account_mode', public.trade_summary_profile_participating_account_mode(p_trade)
      )
    )
  end;
$$;

comment on function public.trade_summary_profile_copy_linkage_json(public.trades) is
  'Public Profile Trades tab — copy-action linkage for client-side grouping (no private journal fields).';
