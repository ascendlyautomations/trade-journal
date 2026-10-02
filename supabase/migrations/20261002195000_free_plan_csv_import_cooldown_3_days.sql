-- Free-plan CSV cooldown is enforced in app code (lib/csvImportGate.ts), not by interval in Postgres.
-- `last_csv_import_at` is set only after a successful import.

comment on column public.profiles.last_csv_import_at is
  'Free tier: timestamp of last successful CSV import; Pro users ignore the cooldown. Free plan: one successful import every 3 days.';
