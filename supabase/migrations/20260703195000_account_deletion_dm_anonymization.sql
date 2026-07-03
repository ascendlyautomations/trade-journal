-- Account deletion: preserve DM history; mark anonymized senders for "Deleted User" UI.

alter table public.messages
  add column if not exists sender_anonymized boolean not null default false;

comment on column public.messages.sender_anonymized is
  'True when the sender deleted their account; UI shows "Deleted User" and disables profile links.';

create index if not exists messages_sender_anonymized_idx
  on public.messages (sender_anonymized)
  where sender_anonymized = true;

-- Ensure auth user removal does not delete conversation messages.
alter table public.messages drop constraint if exists messages_sender_id_fkey;

alter table public.messages
  add constraint messages_sender_id_fkey
  foreign key (sender_id)
  references auth.users (id)
  on delete set null;
