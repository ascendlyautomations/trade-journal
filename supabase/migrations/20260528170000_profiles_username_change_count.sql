alter table public.profiles
  add column if not exists username_change_count integer not null default 0;

comment on column public.profiles.username_change_count is
  'Settings username edits only. 0 = 2 changes remaining, 2 = limit reached. Onboarding and initial signup do not increment.';
