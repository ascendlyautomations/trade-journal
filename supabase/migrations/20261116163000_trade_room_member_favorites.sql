-- Per-member Trade Room favorites (viewer-specific; not room-wide).

alter table public.room_members
  add column if not exists is_favorited boolean not null default false;

comment on column public.room_members.is_favorited is
  'When true, the member has starred this room in Trade Rooms (personal shortcut ordering).';

create index if not exists room_members_user_favorited_active_idx
  on public.room_members (user_id, room_id)
  where is_favorited = true and left_at is null;