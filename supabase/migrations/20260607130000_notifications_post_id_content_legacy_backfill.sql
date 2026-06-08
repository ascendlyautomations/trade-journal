-- Production notifications table predates post_id/content columns.
-- Safe to re-run: all statements are idempotent.

alter table public.notifications
  add column if not exists post_id uuid;

alter table public.notifications
  add column if not exists content text;

update public.notifications
set content = message
where content is null
  and message is not null
  and btrim(message) <> '';

update public.notifications n
set post_id = p.id
from public.posts p
where n.post_id is null
  and n.trade_id is not null
  and p.trade_id = n.trade_id;
