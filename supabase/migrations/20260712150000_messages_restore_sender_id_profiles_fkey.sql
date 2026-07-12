-- Restore messages.sender_id → profiles.id FK required by PostgREST embeds
-- (profiles!sender_id). Regression introduced by
-- 20260703195000_account_deletion_dm_anonymization.sql, which retargeted
-- messages_sender_id_fkey to auth.users and broke DM profile joins (PGRST200).
-- Keep ON DELETE SET NULL so account deletion can null sender_id without
-- deleting DM history.

alter table public.messages
  drop constraint if exists messages_sender_id_fkey;

alter table public.messages
  add constraint messages_sender_id_fkey
  foreign key (sender_id)
  references public.profiles (id)
  on delete set null;
