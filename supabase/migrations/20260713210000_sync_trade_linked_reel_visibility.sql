-- Trade-linked reels: visibility mirrors trades.is_public (trade is source of truth).

-- Backfill existing rows so denormalized visibility matches the linked trade.
update public.reels r
set visibility = case when t.is_public then 'public' else 'private' end
from public.trades t
where r.trade_id = t.id
  and r.visibility is distinct from case when t.is_public then 'public' else 'private' end;

create or replace function public.sync_trade_linked_reel_visibility()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and old.is_public is distinct from new.is_public then
    update public.reels
    set visibility = case when new.is_public then 'public' else 'private' end
    where trade_id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trades_sync_linked_reel_visibility on public.trades;

create trigger trades_sync_linked_reel_visibility
  after update of is_public on public.trades
  for each row
  execute function public.sync_trade_linked_reel_visibility();

comment on function public.sync_trade_linked_reel_visibility() is
  'When a trade share setting changes, mirror visibility onto linked reels. Link is preserved.';
