-- Staging-only reference data. Uses placeholders — replace UUIDs after creating staging Auth users.
-- Does NOT copy production rows, billing, broker tokens, or customer PII.
--
-- Before running:
--   1) Create staging admin via Auth (Dashboard or API): admin@staging.tradetraxs.test
--   2) Replace :STAGING_ADMIN_USER_ID: below with that user's auth.users.id
--   3) Optional: create loadtest users; do not reuse production emails

-- Official / product seeds already come from repo migrations included in baseline
-- (rate_limit_rules, app_monetization_settings, official trade rooms, demo schema DDL).

-- Platform admin gate (required for admin RPCs / demo admin):
-- insert into public.admin_users (user_id)
-- values (':STAGING_ADMIN_USER_ID:'::uuid)
-- on conflict do nothing;

-- Monetization overrides for staging (example — adjust to test matrix):
-- insert into public.app_monetization_account_overrides (user_id, ios_paywall_enabled, note)
-- values (':STAGING_ADMIN_USER_ID:'::uuid, false, 'staging override')
-- on conflict (user_id) do update set ios_paywall_enabled = excluded.ios_paywall_enabled;

-- Achievement catalog: baseline includes table DDL only. If tests need definitions,
-- insert synthetic rows here (never copy from production):
-- insert into public.achievements (id, user_id, type, metadata, ...)
-- values (...);

select '002_staging_reference_seed: edit placeholders before uncommenting inserts' as staging_note;
