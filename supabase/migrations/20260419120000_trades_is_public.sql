-- Community feed visibility: mirrors posts presence / edit-trade toggle.
alter table public.trades
  add column if not exists is_public boolean not null default false;

-- Rows that already have a feed post should reflect public visibility.
update public.trades t
set is_public = true
where exists (
  select 1 from public.posts p where p.trade_id = t.id
);

comment on column public.trades.is_public is
  'When true, trade may appear on the global/following feed (posts row); default private.';
