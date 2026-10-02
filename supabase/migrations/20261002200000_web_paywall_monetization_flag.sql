alter table public.app_monetization_settings
  add column if not exists web_paywall_enabled boolean not null default false;

comment on column public.app_monetization_settings.web_paywall_enabled is
  'When true, the web app may present Stripe checkout and the shared TradeTraxs Pro upgrade experience.';

alter table public.app_monetization_account_overrides
  add column if not exists web_paywall_enabled boolean null;

comment on column public.app_monetization_account_overrides.web_paywall_enabled is
  'Null inherits the global web paywall flag.';
