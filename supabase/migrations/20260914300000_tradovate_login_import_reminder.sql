alter table public.profiles
  add column if not exists tradovate_login_import_reminder_opt_out boolean not null default false;

comment on column public.profiles.tradovate_login_import_reminder_opt_out is
  'When true, skip the post-login Tradovate manual import reminder (Settings import still available).';
