-- Unicode emoji reactions: any valid grapheme, one reaction per user per message (DM + Trade Room).
-- Safe if an earlier draft applied multi-emoji uniqueness — dedupes, restores one-per-user + replace trigger.

-- Dedupe: keep newest row per (message_id, user_id).
delete from public.room_message_reactions r
where r.id in (
  select id
  from (
    select
      id,
      row_number() over (
        partition by message_id, user_id
        order by created_at desc nulls last, id desc
      ) as rn
    from public.room_message_reactions
  ) ranked
  where ranked.rn > 1
);

delete from public.message_reactions r
where r.id in (
  select id
  from (
    select
      id,
      row_number() over (
        partition by message_id, user_id
        order by created_at desc nulls last, id desc
      ) as rn
    from public.message_reactions
  ) ranked
  where ranked.rn > 1
);

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_user_emoji_unique;

alter table public.message_reactions
  drop constraint if exists message_reactions_user_emoji_unique;

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_unique;

alter table public.message_reactions
  drop constraint if exists message_reactions_unique;

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_one_per_user;

alter table public.message_reactions
  drop constraint if exists message_reactions_one_per_user;

alter table public.room_message_reactions
  add constraint room_message_reactions_one_per_user unique (message_id, user_id);

alter table public.message_reactions
  add constraint message_reactions_one_per_user unique (message_id, user_id);

create or replace function public.is_valid_message_reaction(p_reaction text)
returns boolean
language sql
immutable
as $$
  select p_reaction is not null
    and char_length(p_reaction) between 1 and 16
    and octet_length(p_reaction) between 1 and 64
    and btrim(p_reaction) = p_reaction
    and p_reaction !~ '[[:cntrl:]]'
    and p_reaction !~ '^[[:space:]]+$';
$$;

comment on function public.is_valid_message_reaction(text) is
  'Lightweight grapheme-length guard for user-selected Unicode emoji reactions.';

alter table public.message_reactions
  drop constraint if exists message_reactions_reaction_check;

alter table public.message_reactions
  add constraint message_reactions_reaction_check
  check (public.is_valid_message_reaction(reaction));

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_reaction_check;

alter table public.room_message_reactions
  add constraint room_message_reactions_reaction_check
  check (public.is_valid_message_reaction(reaction));

create or replace function public.room_message_reactions_replace_same_user()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  delete from public.room_message_reactions existing
  where existing.message_id = new.message_id
    and existing.user_id = new.user_id
    and existing.id is distinct from new.id;
  return new;
end;
$$;

drop trigger if exists room_message_reactions_replace_same_user
  on public.room_message_reactions;

create trigger room_message_reactions_replace_same_user
  before insert on public.room_message_reactions
  for each row
  execute function public.room_message_reactions_replace_same_user();

create or replace function public.message_reactions_replace_same_user()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  delete from public.message_reactions existing
  where existing.message_id = new.message_id
    and existing.user_id = new.user_id
    and existing.id is distinct from new.id;
  return new;
end;
$$;

drop trigger if exists message_reactions_replace_same_user
  on public.message_reactions;

create trigger message_reactions_replace_same_user
  before insert on public.message_reactions
  for each row
  execute function public.message_reactions_replace_same_user();