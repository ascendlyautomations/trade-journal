-- Trade-level social (distinct from post likes/comments on feed)

create table if not exists public.trade_likes (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references public.trades (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (trade_id, user_id)
);

create table if not exists public.trade_comments (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references public.trades (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists trade_likes_trade_id_idx on public.trade_likes (trade_id);
create index if not exists trade_comments_trade_id_idx on public.trade_comments (trade_id);

alter table public.trade_likes enable row level security;
alter table public.trade_comments enable row level security;

-- trade_likes: explicit authenticated role (see dashboard RLS you can paste)
create policy "Allow insert likes"
  on public.trade_likes
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "Allow delete likes"
  on public.trade_likes
  for delete
  to authenticated
  using (auth.uid() = user_id);

create policy "Allow read likes"
  on public.trade_likes
  for select
  to authenticated
  using (true);

create policy trade_comments_select_authenticated on public.trade_comments
  for select using (auth.role () = 'authenticated');

create policy trade_comments_insert_own on public.trade_comments
  for insert with check (auth.uid () = user_id);
