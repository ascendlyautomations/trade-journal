-- Server-side Trade AI persistence + usage telemetry (extends ai_coach_conversations).
-- Apply manually after 20261128230000_ai_coach_conversations.sql.

alter table public.ai_coach_conversations
  add column if not exists scope jsonb;

-- Allow multiple general Trade AI threads (was one row per user).
drop index if exists public.ai_coach_conversations_general_user_uidx;

alter table public.ai_coach_messages
  add column if not exists display_content text,
  add column if not exists openai_content text,
  add column if not exists attachments jsonb not null default '[]'::jsonb;

create table if not exists public.ai_usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  conversation_id uuid references public.ai_coach_conversations (id) on delete set null,
  route text not null,
  model text,
  prompt_tokens integer,
  completion_tokens integer,
  total_tokens integer,
  created_at timestamptz not null default now()
);

alter table public.ai_usage_events enable row level security;

drop policy if exists ai_usage_events_select_own on public.ai_usage_events;
create policy ai_usage_events_select_own
  on public.ai_usage_events
  for select
  to authenticated
  using (user_id = auth.uid());

grant select on public.ai_usage_events to authenticated;

-- Backfill legacy trade_ai_messages into ai_coach_* when present.
do $bf$
begin
  if to_regclass('public.trade_ai_messages') is null then
    return;
  end if;

  insert into public.ai_coach_conversations (user_id, kind, trade_id, title, last_message_preview, last_message_at, created_at, updated_at)
  select
    m.user_id,
    'trade',
    m.trade_id,
    coalesce(nullif(btrim(t.ticker), ''), 'Trade') || ' · Trade AI',
    (
      select left(btrim(m2.content), 240)
      from public.trade_ai_messages m2
      where m2.trade_id = m.trade_id and m2.user_id = m.user_id
      order by m2.created_at desc
      limit 1
    ),
    (
      select max(m2.created_at)
      from public.trade_ai_messages m2
      where m2.trade_id = m.trade_id and m2.user_id = m.user_id
    ),
    min(m.created_at),
    max(m.created_at)
  from public.trade_ai_messages m
  join public.trades t on t.id = m.trade_id
  where not exists (
    select 1 from public.ai_coach_conversations c
    where c.user_id = m.user_id and c.kind = 'trade' and c.trade_id = m.trade_id
  )
  group by m.user_id, m.trade_id, t.ticker;

  insert into public.ai_coach_messages (
    id, conversation_id, user_id, role, content, display_content, prompt_key, client_message_id, created_at
  )
  select
    m.id,
    c.id,
    m.user_id,
    m.role,
    m.content,
    case when m.role = 'user' then m.content else null end,
    m.prompt_key,
    m.id,
    m.created_at
  from public.trade_ai_messages m
  join public.ai_coach_conversations c
    on c.user_id = m.user_id and c.kind = 'trade' and c.trade_id = m.trade_id
  on conflict (id) do nothing;
end;
$bf$;