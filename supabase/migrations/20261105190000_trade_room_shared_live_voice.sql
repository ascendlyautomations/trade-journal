-- Trade Room shared LiveKit voice: one General Voice channel per room (`tt/{roomId}/voice`).

alter table public.rooms
  add column if not exists live_voice_kind text not null default 'voice_open';

alter table public.rooms
  drop constraint if exists rooms_live_voice_kind_check;

alter table public.rooms
  add constraint rooms_live_voice_kind_check
  check (live_voice_kind in ('off', 'voice_open', 'voice_stage'));

comment on column public.rooms.live_voice_kind is
  'Shared LiveKit voice for the Trade Room: off, voice_open (default), or voice_stage (server-promoted speakers).';

-- Text channels only; voice is no longer modeled as room_sections rows.
update public.room_sections
set live_kind = 'text'
where live_kind in ('voice_open', 'voice_stage');
