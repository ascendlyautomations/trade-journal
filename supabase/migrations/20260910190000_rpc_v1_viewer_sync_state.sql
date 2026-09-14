-- Lightweight viewer sync fingerprints for cache-first launch reconciliation.
-- Scoped to auth.uid(); tiny response — no row payloads.

create or replace function public.rpc_v1_viewer_sync_state()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_trades_count int;
  v_trades_max_created timestamptz;
  v_trades_checksum bigint;
  v_accounts_count int;
  v_accounts_max_created timestamptz;
  v_accounts_checksum bigint;
  v_profile_checksum text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select
    count(*)::int,
    max(t.created_at),
    coalesce(
      sum(
        hashtextextended(
          t.id::text || '|' ||
          coalesce(t.pnl::text, '') || '|' ||
          coalesce(t.notes, '') || '|' ||
          coalesce(t.ticker, '') || '|' ||
          coalesce(t.is_public::text, '') || '|' ||
          coalesce(t.image_url, '') || '|' ||
          coalesce(t.trade_date::text, '') || '|' ||
          coalesce(t.account_id, '') || '|' ||
          coalesce(t.rr::text, ''),
          0
        )
      ),
      0
    )::bigint
  into v_trades_count, v_trades_max_created, v_trades_checksum
  from public.trades t
  where t.user_id = v_uid;

  select
    count(*)::int,
    max(a.created_at),
    coalesce(
      sum(
        hashtextextended(
          a.id::text || '|' ||
          coalesce(a.name, '') || '|' ||
          coalesce(a.mode, '') || '|' ||
          coalesce(a.account_size, '') || '|' ||
          coalesce(a.is_active::text, '') || '|' ||
          coalesce(a.can_add_trades::text, '') || '|' ||
          coalesce(a.category, '') || '|' ||
          coalesce(a.note, ''),
          0
        )
      ),
      0
    )::bigint
  into v_accounts_count, v_accounts_max_created, v_accounts_checksum
  from public.accounts a
  where a.user_id = v_uid;

  select md5(
    coalesce(p.username, '') || '|' ||
    coalesce(p.name, '') || '|' ||
    coalesce(p.bio, '') || '|' ||
    coalesce(p.avatar_url, '') || '|' ||
    coalesce(p.trader_type, '') || '|' ||
    coalesce(p.trading_style, '') || '|' ||
    coalesce(p.primary_market, '') || '|' ||
    coalesce(p.onboarding_completed::text, '') || '|' ||
    coalesce(p.is_private::text, '')
  )
  into v_profile_checksum
  from public.profiles p
  where p.id = v_uid;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'trades', jsonb_build_object(
        'count', v_trades_count,
        'max_created_at', case
          when v_trades_max_created is null then null
          else to_char(v_trades_max_created at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        end,
        'checksum', v_trades_checksum
      ),
      'accounts', jsonb_build_object(
        'count', v_accounts_count,
        'max_created_at', case
          when v_accounts_max_created is null then null
          else to_char(v_accounts_max_created at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        end,
        'checksum', v_accounts_checksum
      ),
      'profile', jsonb_build_object(
        'checksum', v_profile_checksum
      )
    )
  );
end;
$$;

revoke all on function public.rpc_v1_viewer_sync_state() from public;
grant execute on function public.rpc_v1_viewer_sync_state() to authenticated;
