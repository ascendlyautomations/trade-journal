-- Allow heart on DM + Trade Room message reactions (double-tap default).

alter table public.message_reactions
  drop constraint if exists message_reactions_reaction_check;

alter table public.message_reactions
  add constraint message_reactions_reaction_check
  check (reaction in ('❤️', '👍', '🔥', '😂', '‼️'));

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_reaction_check;

alter table public.room_message_reactions
  add constraint room_message_reactions_reaction_check
  check (reaction in ('❤️', '👍', '🔥', '😂', '‼️'));
