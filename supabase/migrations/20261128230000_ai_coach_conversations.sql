-- Unified AI coach threads (Trade AI per trade, General Trade AI, Psychology Coach).
-- Complements legacy public.trade_ai_messages (trade-scoped); new threads backfilled from client.

create table if not exists public.ai_coach_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('trade', 'general_trade', 'psychology')),
  trade_id uuid references public.trades (id) on delete cascade,
  title text,
  scope_label text,
  scope_fingerprint text,
  facts_hash text,
  last_message_preview text,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_coach_conversations_trade_kind_check check (
    (kind = 'trade' and trade_id is not null)
    or (kind in ('general_trade', 'psychology') and trade_id is null)
  )
);

create unique index if not exists ai_coach_conversations_trade_user_uidx
  on public.ai_coach_conversations (user_id, trade_id)
  where kind = 'trade' and trade_id is not null;

create unique index if not exists ai_coach_conversations_general_user_uidx
  on public.ai_coach_conversations (user_id)
  where kind = 'general_trade';

create index if not exists ai_coach_conversations_user_updated_idx
  on public.ai_coach_conversations (user_id, last_message_at desc);

comment on table public.ai_coach_conversations is
  'Owner-only AI coaching threads for Messages inbox and multi-session Psychology Coach.';

create table if not exists public.ai_coach_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.ai_coach_conversations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  prompt_key text,
  client_message_id uuid,
  created_at timestamptz not null default now(),
  constraint ai_coach_messages_user_conversation_fk check (true)
);

create unique index if not exists ai_coach_messages_client_id_uidx
  on public.ai_coach_messages (user_id, client_message_id)
  where client_message_id is not null;

create index if not exists ai_coach_messages_conversation_created_idx
  on public.ai_coach_messages (conversation_id, created_at asc);

comment on table public.ai_coach_messages is
  'Append-only AI coach turns; client_message_id supports idempotent inserts.';

create or replace function public.ai_coach_conversations_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists ai_coach_conversations_set_updated_at_trigger on public.ai_coach_conversations;
create trigger ai_coach_conversations_set_updated_at_trigger
  before update on public.ai_coach_conversations
  for each row
  execute function public.ai_coach_conversations_set_updated_at();

create or replace function public.ai_coach_conversations_touch_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.ai_coach_conversations c
  set
    last_message_at = new.created_at,
    last_message_preview = left(new.content, 240),
    updated_at = now()
  where c.id = new.conversation_id
    and c.user_id = new.user_id;
  return new;
end;
$$;

drop trigger if exists ai_coach_messages_touch_conversation on public.ai_coach_messages;
create trigger ai_coach_messages_touch_conversation
  after insert on public.ai_coach_messages
  for each row
  execute function public.ai_coach_conversations_touch_from_message();

alter table public.ai_coach_conversations enable row level security;
alter table public.ai_coach_messages enable row level security;

drop policy if exists ai_coach_conversations_select_own on public.ai_coach_conversations;
create policy ai_coach_conversations_select_own
  on public.ai_coach_conversations
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists ai_coach_conversations_insert_own on public.ai_coach_conversations;
create policy ai_coach_conversations_insert_own
  on public.ai_coach_conversations
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists ai_coach_conversations_update_own on public.ai_coach_conversations;
create policy ai_coach_conversations_update_own
  on public.ai_coach_conversations
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists ai_coach_conversations_delete_own on public.ai_coach_conversations;
create policy ai_coach_conversations_delete_own
  on public.ai_coach_conversations
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists ai_coach_messages_select_own on public.ai_coach_messages;
create policy ai_coach_messages_select_own
  on public.ai_coach_messages
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists ai_coach_messages_insert_own on public.ai_coach_messages;
create policy ai_coach_messages_insert_own
  on public.ai_coach_messages
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.ai_coach_conversations c
      where c.id = conversation_id
        and c.user_id = auth.uid()
    )
    and (
      not exists (
        select 1
        from public.ai_coach_conversations c
        where c.id = conversation_id
          and c.kind = 'trade'
      )
      or exists (
        select 1
        from public.ai_coach_conversations c
        join public.trades t on t.id = c.trade_id
        where c.id = conversation_id
          and c.user_id = auth.uid()
          and t.user_id = auth.uid()
      )
    )
  );

grant select, insert, update, delete on public.ai_coach_conversations to authenticated;
grant select, insert on public.ai_coach_messages to authenticated;

-- TraxPro gate (optional table, mirror trade_ai_messages pattern).
create or replace function public.ai_coach_messages_enforce_traxpro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  perform public.traxpro_assert_feature_access(new.user_id, 'ai_analyst');
  return new;
end;
$$;

comment on function public.ai_coach_messages_enforce_traxpro() is
  'Requires TraxPro to append unified AI coach messages when entitlement enforcement is on.';

drop trigger if exists ai_coach_messages_enforce_traxpro on public.ai_coach_messages;
create trigger ai_coach_messages_enforce_traxpro
  before insert on public.ai_coach_messages
  for each row
  execute function public.ai_coach_messages_enforce_traxpro();