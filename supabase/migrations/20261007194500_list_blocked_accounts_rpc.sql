-- Settings → Privacy → Blocked Accounts: profile fields for users the viewer blocked.
-- Direct PostgREST embeds on profiles fail under profiles_select_hide_blocked; definer read is scoped to blocker rows only.

create or replace function public.list_blocked_accounts()
returns table (
  blocked_id uuid,
  created_at timestamptz,
  username text,
  name text,
  avatar_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    ub.blocked_id,
    ub.created_at,
    p.username,
    p.name,
    p.avatar_url
  from public.user_blocks ub
  join public.profiles p on p.id = ub.blocked_id
  where ub.blocker_id = auth.uid()
  order by ub.created_at desc;
$$;

comment on function public.list_blocked_accounts() is
  'Returns blocked users with profile presentation for the authenticated blocker (Settings list).';

revoke all on function public.list_blocked_accounts() from public;
grant execute on function public.list_blocked_accounts() to authenticated;
