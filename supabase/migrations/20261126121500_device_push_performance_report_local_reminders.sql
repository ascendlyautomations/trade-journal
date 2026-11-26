-- iOS sets this after verified on-device Performance Report reminders are scheduled (Pro + auth).
-- Server weekly APNs skip only when at least one install has local reminders active — not merely an iOS token.

alter table public.device_push_tokens
  add column if not exists performance_report_local_reminders_active boolean not null default false;

comment on column public.device_push_tokens.performance_report_local_reminders_active is
  'True when this iOS install has confirmed pending local Performance Report weekly+monthly reminders.';

create index if not exists device_push_tokens_user_local_perf_reminders_idx
  on public.device_push_tokens (user_id)
  where platform = 'ios' and performance_report_local_reminders_active = true;