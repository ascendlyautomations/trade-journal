-- Performance: indexes for the primary trades access patterns (dashboard, trades list, checklist counts).

create index if not exists trades_user_id_created_at_idx
  on public.trades (user_id, created_at desc);

create index if not exists trades_user_id_is_public_idx
  on public.trades (user_id, is_public)
  where is_public = true;

create index if not exists trades_account_id_trade_date_idx
  on public.trades (account_id, trade_date, entry_time);

-- Navbar unread notification badge: user_id + read=false filter.
create index if not exists notifications_user_id_unread_idx
  on public.notifications (user_id)
  where read = false;
