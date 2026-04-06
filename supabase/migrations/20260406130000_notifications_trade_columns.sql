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
  add column if not exists content text;

alter table public.notifications
  add column if not exists trade_id uuid references public.trades (id) on delete set null;

alter table public.notifications
  add column if not exists read boolean not null default false;
