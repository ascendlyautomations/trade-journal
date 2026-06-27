alter table public.profiles
  add column if not exists has_email_password boolean not null default false;

comment on column public.profiles.has_email_password is
  'True after the user sets an email/password login (e.g. Google account adds a password). Source of truth for Settings password UI.';

-- Email/password signups already authenticate with a password.
update public.profiles p
set has_email_password = true
where exists (
  select 1
  from auth.users u
  where u.id = p.id
    and coalesce(u.raw_app_meta_data->>'provider', '') = 'email'
);

-- Google (or other OAuth) users who already linked an email identity.
update public.profiles p
set has_email_password = true
where has_email_password = false
  and exists (
    select 1
    from auth.identities i
    where i.user_id = p.id
      and i.provider = 'email'
  );
