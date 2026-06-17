alter table public.profiles
  add column if not exists has_seen_onboarding_complete_popup boolean not null default false;

comment on column public.profiles.has_seen_onboarding_complete_popup is
  'User dismissed the Getting Started onboarding completion popup; show at most once per account.';

-- Reliable completion-popup dismiss persistence (SECURITY DEFINER bypasses RLS edge cases).

create or replace function public.mark_onboarding_complete_popup_seen()
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
  set has_seen_onboarding_complete_popup = true
  where id = auth.uid();

  return found;
end;
$$;

revoke all on function public.mark_onboarding_complete_popup_seen() from public;
grant execute on function public.mark_onboarding_complete_popup_seen() to authenticated;

comment on function public.mark_onboarding_complete_popup_seen() is
  'Sets profiles.has_seen_onboarding_complete_popup = true for the current user.';
