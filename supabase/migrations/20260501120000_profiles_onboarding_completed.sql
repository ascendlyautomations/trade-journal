-- Gate post-signup "import CSV" onboarding modal
alter table public.profiles
  add column if not exists onboarding_completed boolean not null default false;

comment on column public.profiles.onboarding_completed is
  'True after user skips or completes post-setup CSV import onboarding.';

-- Existing users should not see the modal retroactively
update public.profiles
set onboarding_completed = true
where coalesce(onboarding_completed, false) = false;
