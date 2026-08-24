-- PGRST201 repair: remove redundant message_id-only FK on room_message_reactions.
--
-- Before: two PostgREST relationships room_messages ↔ room_message_reactions:
--   1. room_message_reactions_message_id_fkey (message_id → room_messages.id)
--   2. room_message_reactions_message_room_fkey (message_id, room_id) composite
-- After: composite FK only — same ON DELETE CASCADE semantics for reactions.

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_message_id_fkey;

-- Composite FK already exists from 20260822220000 with ON DELETE CASCADE.
-- Re-assert name/cascade in case of partial apply (idempotent).
alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_message_room_fkey;

alter table public.room_message_reactions
  add constraint room_message_reactions_message_room_fkey
  foreign key (message_id, room_id)
  references public.room_messages (id, room_id)
  on delete cascade;

comment on constraint room_message_reactions_message_room_fkey
  on public.room_message_reactions is
  'Single PostgREST embed path to room_messages; deletes reactions when message deleted.';
