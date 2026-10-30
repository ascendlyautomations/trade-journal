-- Staging-safe bucket definitions missing from migration INSERTs.
-- Idempotent. No user objects or secrets.

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('screenshots', 'screenshots', true),
  ('bug-reports', 'bug-reports', false),
  ('email-assets', 'email-assets', true),
  ('group-avatars', 'group-avatars', true)
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public;
