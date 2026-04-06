-- Per-message read receipts: array of user ids who have seen the message
alter table public.messages
  add column if not exists seen_by jsonb default '[]'::jsonb;
