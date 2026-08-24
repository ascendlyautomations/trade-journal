-- Rollback: remove_redundant_reaction_message_fk (PGRST201 repair)
--
-- WARNING: Re-adding room_message_reactions_message_id_fkey restores TWO
-- PostgREST relationships and PGRST201 embed ambiguity unless every client
-- query uses explicit room_message_reactions!room_message_reactions_message_room_fkey(...).

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_message_room_fkey;

alter table public.room_message_reactions
  add constraint room_message_reactions_message_room_fkey
  foreign key (message_id, room_id)
  references public.room_messages (id, room_id)
  on delete cascade;

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_message_id_fkey;

alter table public.room_message_reactions
  add constraint room_message_reactions_message_id_fkey
  foreign key (message_id)
  references public.room_messages (id)
  on delete cascade;
