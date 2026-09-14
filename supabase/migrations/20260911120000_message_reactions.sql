-- DM message reactions — same emoji set + participant RLS as Trade Rooms.

create table if not exists public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null,
  created_at timestamptz not null default now(),
  constraint message_reactions_reaction_check
    check (reaction in ('👍', '🔥', '😂', '‼️')),
  constraint message_reactions_unique unique (message_id, user_id, reaction)
);

create index if not exists message_reactions_conversation_id_idx
  on public.message_reactions (conversation_id);

create index if not exists message_reactions_message_id_idx
  on public.message_reactions (message_id);

alter table public.message_reactions enable row level security;

drop policy if exists "message_reactions_select_participant" on public.message_reactions;
create policy "message_reactions_select_participant"
  on public.message_reactions
  for select
  to authenticated
  using (public.is_conversation_participant(conversation_id, auth.uid()));

drop policy if exists "message_reactions_insert_participant" on public.message_reactions;
create policy "message_reactions_insert_participant"
  on public.message_reactions
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_conversation_participant(conversation_id, auth.uid())
  );

drop policy if exists "message_reactions_delete_own" on public.message_reactions;
create policy "message_reactions_delete_own"
  on public.message_reactions
  for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, delete on table public.message_reactions to authenticated;

create or replace function public.message_reactions_set_conversation_id()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if new.conversation_id is null then
    select m.conversation_id into new.conversation_id
    from public.messages m
    where m.id = new.message_id;
  end if;
  if new.conversation_id is null then
    raise exception 'message_reactions: message % not found', new.message_id;
  end if;
  return new;
end;
$$;

drop trigger if exists message_reactions_set_conversation_id on public.message_reactions;
create trigger message_reactions_set_conversation_id
  before insert on public.message_reactions
  for each row
  execute function public.message_reactions_set_conversation_id();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end $$;

create or replace function public.rpc_v1_conversation_thread_message_row(p_message_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', m.id,
    'conversation_id', m.conversation_id,
    'sender_id', m.sender_id,
    'sender_anonymized', coalesce(m.sender_anonymized, false),
    'content', m.content,
    'created_at', case
      when m.created_at is null then null
      else to_char(timezone('utc', m.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    end,
    'seen_by', coalesce(m.seen_by, '{}'::uuid[]),
    'type', m.type,
    'trade_id', m.trade_id,
    'post_id', m.post_id,
    'profile_post_id', m.profile_post_id,
    'achievement_post_id', m.achievement_post_id,
    'reel_id', m.reel_id,
    'parent_message_id', m.parent_message_id,
    'deleted_for_everyone', coalesce(m.deleted_for_everyone, false),
    'image_url', m.image_url,
    'audio_url', m.audio_url,
    'audio_duration_ms', m.audio_duration_ms,
    'is_system', coalesce(m.is_system, false),
    'profiles', case
      when m.sender_id is null then null
      else (
        select jsonb_build_object(
          'username', pr.username,
          'avatar_url', pr.avatar_url
        )
        from public.profiles pr
        where pr.id = m.sender_id
      )
    end,
    'message_reactions', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'message_id', r.message_id,
            'user_id', r.user_id,
            'reaction', r.reaction
          )
          order by r.created_at asc, r.id asc
        )
        from public.message_reactions r
        where r.message_id = m.id
      ),
      '[]'::jsonb
    )
  )
  from public.messages m
  where m.id = p_message_id;
$$;

revoke all on function public.rpc_v1_conversation_thread_message_row(uuid) from public;
grant execute on function public.rpc_v1_conversation_thread_message_row(uuid) to authenticated;
