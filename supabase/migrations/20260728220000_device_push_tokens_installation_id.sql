-- Stable per-install identity for APNs token rotation.
-- Same installation (identifierForVendor) keeps one row; device_token updates in place.
-- Different devices (iPhone vs iPad) keep separate rows.

alter table public.device_push_tokens
  add column if not exists installation_id text;

comment on column public.device_push_tokens.installation_id is
  'Stable install id (iOS identifierForVendor). Used to replace rotated APNs tokens without orphaning stale rows.';

create unique index if not exists device_push_tokens_installation_id_key
  on public.device_push_tokens (installation_id)
  where installation_id is not null;
