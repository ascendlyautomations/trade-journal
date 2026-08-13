-- Native Trade AI conversation history (append-only per trade / user).
-- Used by the iOS Trade Detail coach experience. Web analyst continues to use trades.ai_feedback.

create table if not exists public.trade_ai_messages (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references public.trades (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  prompt_key text,
  created_at timestamptz not null default now()
);

create index if not exists trade_ai_messages_trade_user_created_idx
  on public.trade_ai_messages (trade_id, user_id, created_at asc);

alter table public.trade_ai_messages enable row level security;

drop policy if exists trade_ai_messages_select_own on public.trade_ai_messages;
create policy trade_ai_messages_select_own
  on public.trade_ai_messages
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists trade_ai_messages_insert_own on public.trade_ai_messages;
create policy trade_ai_messages_insert_own
  on public.trade_ai_messages
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.trades t
      where t.id = trade_id
        and t.user_id = auth.uid()
    )
  );

grant select, insert on public.trade_ai_messages to authenticated;
