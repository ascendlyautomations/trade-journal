-- Reliable intro-dismiss persistence (SECURITY DEFINER bypasses RLS edge cases).

create or replace function public.mark_getting_started_intro_seen()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  update public.profiles
  set has_seen_getting_started_intro = true
  where id = auth.uid();

  return found;
end;
$$;

revoke all on function public.mark_getting_started_intro_seen() from public;
grant execute on function public.mark_getting_started_intro_seen() to authenticated;

comment on function public.mark_getting_started_intro_seen() is
  'Sets profiles.has_seen_getting_started_intro = true for the current user.';
