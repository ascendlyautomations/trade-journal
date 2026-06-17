alter table public.profiles
  add column if not exists has_seen_getting_started_intro boolean not null default false;

comment on column public.profiles.has_seen_getting_started_intro is
  'User dismissed the Getting Started introduction popup; show at most once per account.';

-- Existing users who finished profile onboarding have already been introduced.
update public.profiles
set has_seen_getting_started_intro = true
where onboarding_completed = true
  and coalesce(has_seen_getting_started_intro, false) = false;
