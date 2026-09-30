-- Authenticated journal privacy: RLS can expose rows to non-owners, but column
-- grants must not expose owner journal / account metadata on public.trades.
-- Non-owner social reads stay on public.trades_public_read (security invoker).
-- Owner full reads use SECURITY DEFINER RPCs bound to auth.uid().

-- ---------------------------------------------------------------------------
-- Column boundary (mirror anon safe projection on public.trades)
-- ---------------------------------------------------------------------------

revoke select on table public.trades from authenticated;

grant select (
  id,
  user_id,
  created_at,
  date,
  trade_date,
  pnl,
  rr,
  points,
  contracts,
  session,
  ticker,
  direction,
  public_description,
  is_public,
  is_pinned,
  image_url,
  image_crop,
  image_display_mode,
  entry_time,
  exit_time,
  entry_price,
  exit_price,
  duration_seconds,
  duration_text,
  account_type,
  mode,
  trade_mode,
  trade_type,
  timeframe,
  market_condition,
  first_published_at,
  copy_trading_group_id,
  copied_account_ids
) on table public.trades to authenticated;

-- ---------------------------------------------------------------------------
-- Owner-only full trade reads (never trust a supplied user_id)
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_trade_owner_read(p_trade_id text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select to_jsonb(t.*)
  from public.trades t
  where t.id = p_trade_id::uuid
    and t.user_id = auth.uid();
$$;

comment on function public.rpc_v1_trade_owner_read(text) is
  'Owner-only full trade row (journal + account metadata). Ignores non-owned ids.';

revoke all on function public.rpc_v1_trade_owner_read(text) from public;
grant execute on function public.rpc_v1_trade_owner_read(text) to authenticated;

create or replace function public.rpc_v1_trades_owner_rows(
  p_trade_ids text[] default null,
  p_limit int default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_limit int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_trade_ids is not null and cardinality(p_trade_ids) > 0 then
    return coalesce(
      (
        select jsonb_agg(to_jsonb(t.*) order by t.created_at desc)
        from public.trades t
        where t.user_id = v_uid
          and t.id::text = any (p_trade_ids)
      ),
      '[]'::jsonb
    );
  end if;

  if p_limit is not null then
    v_limit := greatest(least(p_limit, 500), 1);
    return coalesce(
      (
        select jsonb_agg(to_jsonb(x.*) order by x.created_at desc)
        from (
          select t.*
          from public.trades t
          where t.user_id = v_uid
          order by t.created_at desc
          limit v_limit
        ) x
      ),
      '[]'::jsonb
    );
  end if;

  return coalesce(
    (
      select jsonb_agg(to_jsonb(t.*) order by t.created_at desc)
      from public.trades t
      where t.user_id = v_uid
    ),
    '[]'::jsonb
  );
end;
$$;

comment on function public.rpc_v1_trades_owner_rows(text[], int) is
  'Owner-only trade rows (full projection). Optional id filter or limit for app cache.';

revoke all on function public.rpc_v1_trades_owner_rows(text[], int) from public;
grant execute on function public.rpc_v1_trades_owner_rows(text[], int) to authenticated;

-- Owner-scoped bootstrap RPCs must keep reading journal columns after authenticated
-- column REVOKE on public.trades (still bound to auth.uid() inside each function).
alter function public.rpc_v1_trades_list_bootstrap(
  integer,
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  text,
  numeric,
  numeric,
  text,
  text
) security definer;

alter function public.rpc_v1_trades_list_bootstrap(
  integer,
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text
) security definer;

alter function public.rpc_v1_trades_list_bootstrap_v2(
  integer,
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text
) security definer;

alter function public.rpc_v1_dashboard_bootstrap(uuid, integer) security definer;
