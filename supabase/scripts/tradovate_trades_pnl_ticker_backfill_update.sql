-- Run ONLY after tradovate_trades_pnl_ticker_backfill.sql dry-run looks correct.
-- Backfilled pnl = points × contracts × value_per_point (fees not in DB → same as importer with zero fees).

begin;

with repair_candidates as (
  select
    t.id as trade_id,
    t.ticker as old_ticker,
    t.broker_lifecycle_id,
    t.broker_integration_account_id,
    t.points,
    t.contracts,
    t.pnl as old_pnl,
    coalesce(
      nullif(trim(e.symbol_root), ''),
      nullif(trim(regexp_replace(e.contract_name, '[FGHJKMNQUVXZ][0-9]{1,2}$', '')), '')
    ) as exec_symbol_hint
  from public.trades t
  left join lateral (
    select e1.symbol_root, e1.contract_name
    from public.broker_integration_executions e1
    where e1.user_id = t.user_id
      and e1.provider = 'tradovate'
      and e1.broker_integration_account_id = t.broker_integration_account_id
      and (
        e1.external_contract_id = t.ticker
        or e1.external_contract_id = nullif(trim(split_part(t.broker_lifecycle_id, ':', 4)), '')
      )
      and coalesce(nullif(trim(e1.symbol_root), ''), nullif(trim(e1.contract_name), '')) is not null
    order by e1.executed_at desc
    limit 1
  ) e on true
  where t.import_source = 'tradovate'
    and t.broker_lifecycle_id is not null
    and (t.pnl is null or t.ticker ~ '^[0-9]+$')
),
resolved as (
  select
    c.*,
    upper(
      case
        when c.exec_symbol_hint ~ '^[A-Z0-9]{1,6}[FGHJKMNQUVXZ][0-9]{1,2}$'
          then regexp_replace(c.exec_symbol_hint, '[FGHJKMNQUVXZ][0-9]{1,2}$', '')
        else c.exec_symbol_hint
      end
    ) as resolved_root
  from repair_candidates c
),
with_vpp as (
  select
    r.trade_id,
    r.resolved_root,
    r.points,
    r.contracts,
    case upper(r.resolved_root)
      when 'MNQ' then 2
      when 'MGC' then 10
      when 'ES' then 50
      when 'MES' then 5
      when 'NQ' then 20
      when 'YM' then 5
      when 'MYM' then 0.5
      when 'RTY' then 50
      when 'M2K' then 5
      when 'CL' then 1000
      when 'MCL' then 100
      when 'GC' then 100
      when 'SI' then 5000
      when 'SIL' then 1000
      when 'NG' then 10000
      when 'ZB' then 1000
      when 'ZN' then 1000
      when 'ZF' then 1000
      when 'ZT' then 2000
      when 'UB' then 1000
      when 'HO' then 42000
      when 'RB' then 42000
      when 'BTC' then 5
      when 'MBT' then 0.1
      when 'ETH' then 50
      when 'MET' then 0.1
      else null
    end as value_per_point
  from resolved r
  where r.resolved_root is not null
    and r.resolved_root !~ '^[0-9]+$'
    and r.points is not null
    and r.contracts is not null
),
final as (
  select
    trade_id,
    resolved_root as new_ticker,
    round((points * contracts * value_per_point)::numeric, 2) as new_pnl
  from with_vpp
  where value_per_point is not null
)
update public.trades t
set
  ticker = f.new_ticker,
  pnl = f.new_pnl
from final f
where t.id = f.trade_id
  and t.import_source = 'tradovate';

-- commit;
