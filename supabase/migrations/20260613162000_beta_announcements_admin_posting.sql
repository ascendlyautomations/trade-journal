-- TradeTraxs Beta: announcements is admin-post-only (members can read).
-- Scoped to tradetraxs-beta / announcements only; other rooms unchanged.

update public.room_sections s
set allow_members_chat = false
from public.rooms r
where s.room_id = r.id
  and lower(trim(coalesce(r.slug, ''))) = 'tradetraxs-beta'
  and lower(trim(s.name)) = 'announcements';

create or replace function public.room_message_insert_section_allowed(
  p_room_id uuid,
  p_section_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select case
    when p_section_id is null then true
    when not exists (
      select 1
      from public.room_sections rs
      join public.rooms r on r.id = rs.room_id
      where rs.id = p_section_id
        and rs.room_id = p_room_id
        and lower(trim(coalesce(r.slug, ''))) = 'tradetraxs-beta'
        and lower(trim(rs.name)) = 'announcements'
        and rs.allow_members_chat is false
    ) then true
    when public.is_room_owner(p_room_id, p_user_id) then true
    when exists (
      select 1
      from public.admin_users au
      where au.user_id = p_user_id
    ) then true
    else false
  end;
$$;

drop policy if exists "room_messages_insert_member" on public.room_messages;

create policy "room_messages_insert_member"
  on public.room_messages
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
    and public.room_message_insert_section_allowed(room_id, section_id, auth.uid())
  );
