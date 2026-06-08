-- Trade + feed notifications: optional body text, trade link, read flag
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid (),
  created_at timestamptz not null default now (),
  user_id uuid not null references auth.users (id) on delete cascade,
  sender_id uuid references auth.users (id) on delete set null,
  type text not null,
  post_id uuid,
  trade_id uuid references public.trades (id) on delete set null,
  content text,
  read boolean not null default false
);

alter table public.notifications
  add column if not exists post_id uuid;

alter table public.notifications
  add column if not exists content text;

alter table public.notifications
  add column if not exists trade_id uuid references public.trades (id) on delete set null;

alter table public.notifications
  add column if not exists read boolean not null default false;

-- Legacy installs used `message` for body text.
update public.notifications
set content = message
where content is null
  and message is not null
  and btrim(message) <> '';

-- Backfill post_id from trade-linked posts when possible.
update public.notifications n
set post_id = p.id
from public.posts p
where n.post_id is null
  and n.trade_id is not null
  and p.trade_id = n.trade_id;
