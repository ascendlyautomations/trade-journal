-- Per-user notification delivery preferences (default: all enabled).

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  notifications_enabled boolean not null default true,
  likes_enabled boolean not null default true,
  comments_enabled boolean not null default true,
  replies_enabled boolean not null default true,
  mentions_enabled boolean not null default true,
  reactions_enabled boolean not null default true,
  followers_enabled boolean not null default true,
  follow_requests_enabled boolean not null default true,
  follow_request_accepts_enabled boolean not null default true,
  direct_messages_enabled boolean not null default true,
  story_replies_enabled boolean not null default true,
  shares_enabled boolean not null default true,
  room_messages_enabled boolean not null default true,
  room_mentions_enabled boolean not null default true,
  room_joins_enabled boolean not null default true,
  achievement_likes_enabled boolean not null default true,
  achievement_comments_enabled boolean not null default true,
  achievement_unlocks_enabled boolean not null default true,
  product_updates_enabled boolean not null default true,
  maintenance_enabled boolean not null default true,
  announcements_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

comment on table public.notification_preferences is
  'Per-user notification delivery toggles. Master switch: notifications_enabled.';

-- Backfill existing profiles with defaults (all true).
insert into public.notification_preferences (user_id)
select p.id
from public.profiles p
on conflict (user_id) do nothing;

create or replace function public.ensure_notification_preferences_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists profiles_ensure_notification_preferences on public.profiles;
create trigger profiles_ensure_notification_preferences
  after insert on public.profiles
  for each row
  execute function public.ensure_notification_preferences_row();

alter table public.notification_preferences enable row level security;

drop policy if exists notification_preferences_select_own on public.notification_preferences;
create policy notification_preferences_select_own
  on public.notification_preferences
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists notification_preferences_update_own on public.notification_preferences;
create policy notification_preferences_update_own
  on public.notification_preferences
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists notification_preferences_insert_own on public.notification_preferences;
create policy notification_preferences_insert_own
  on public.notification_preferences
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- Central delivery guard for all notification inserts (including service role).
create or replace function public.should_deliver_notification(
  p_recipient_id uuid,
  p_type text,
  p_achievement_post_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  prefs public.notification_preferences%rowtype;
begin
  if p_recipient_id is null then
    return false;
  end if;

  select * into prefs
  from public.notification_preferences
  where user_id = p_recipient_id;

  if not found then
    return true;
  end if;

  if not prefs.notifications_enabled then
    return false;
  end if;

  case p_type
    when 'like' then
      if p_achievement_post_id is not null then
        return prefs.achievement_likes_enabled;
      end if;
      return prefs.likes_enabled;
    when 'comment' then
      if p_achievement_post_id is not null then
        return prefs.achievement_comments_enabled;
      end if;
      -- Reply / mention / top-level comment kinds are enforced in the API route.
      return true;
    when 'follow' then
      return prefs.followers_enabled;
    when 'follow_request' then
      return prefs.follow_requests_enabled;
    when 'room_message' then
      return prefs.room_messages_enabled;
    when 'room_join' then
      return prefs.room_joins_enabled;
    when 'message' then
      return prefs.direct_messages_enabled;
    else
      return true;
  end case;
end;
$$;

create or replace function public.guard_notification_preferences()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.should_deliver_notification(
    new.user_id,
    new.type,
    new.achievement_post_id
  ) then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_preferences_guard on public.notifications;
create trigger notifications_preferences_guard
  before insert on public.notifications
  for each row
  execute function public.guard_notification_preferences();
