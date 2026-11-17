-- Saturday weekly trading report push.
-- pg_cron calls the existing BFF route via pg_net (no Vercel cron).
--
-- After deploy, configure the bearer once per environment. Do not commit the secret.
--
-- insert into private.weekly_report_push_config (id, bff_url, bearer_secret)
-- values (
--   1,
--   'https://www.tradetraxs.com/api/cron/weekly-trading-reports',
--   '<same value as CRON_SECRET on Vercel>'
-- )
-- on conflict (id) do update set
--   bff_url = excluded.bff_url,
--   bearer_secret = excluded.bearer_secret,
--   updated_at = timezone('utc', now());

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;

create schema if not exists private;

create table if not exists private.weekly_report_push_config (
  id smallint primary key check (id = 1),
  bff_url text not null,
  bearer_secret text not null,
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table private.weekly_report_push_config is
  'Single-row config: GET URL for /api/cron/weekly-trading-reports and Bearer secret matching CRON_SECRET. Insert after deploy; never store the secret in a migration.';

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to postgres, service_role;
revoke all on table private.weekly_report_push_config from public, anon, authenticated;
grant select on table private.weekly_report_push_config to postgres, service_role;

-- One jsonb array so PostgREST's row cap cannot truncate the user list.
create or replace function public.weekly_trading_report_eligible_user_ids(
  p_start date,
  p_end date
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    (
      select jsonb_agg(distinct t.user_id)
      from public.trades t
      where t.user_id is not null
        and coalesce(t.mode, '') <> 'backtest'
        and public.analytics_calendar_day(t.entry_time, t.exit_time, t.created_at)
            between p_start and p_end
    ),
    '[]'::jsonb
  );
$$;

comment on function public.weekly_trading_report_eligible_user_ids(date, date) is
  'Distinct non-backtest owners with an Eastern trade day in [p_start, p_end]. Service role only.';

revoke all on function public.weekly_trading_report_eligible_user_ids(date, date) from public, anon, authenticated;
grant execute on function public.weekly_trading_report_eligible_user_ids(date, date) to service_role;

create or replace function private.weekly_report_push_http_dispatch()
returns bigint
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_url text;
  v_secret text;
  v_request_id bigint;
begin
  select c.bff_url, c.bearer_secret
  into v_url, v_secret
  from private.weekly_report_push_config c
  where c.id = 1;

  if v_url is null
    or v_secret is null
    or length(trim(v_url)) = 0
    or length(trim(v_secret)) = 0
  then
    return null;
  end if;

  select net.http_get(
    url := trim(v_url),
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || trim(v_secret)
    ),
    timeout_milliseconds := 70000
  )
  into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.weekly_report_push_http_dispatch() from public, anon, authenticated;

do $$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname = 'weekly-trading-report-push';

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;

  perform cron.schedule(
    'weekly-trading-report-push',
    '0 17 * * 6',
    $cron$select private.weekly_report_push_http_dispatch();$cron$
  );

  select jobid into v_jobid
  from cron.job
  where jobname = 'weekly-trading-report-push-retry';

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;

  perform cron.schedule(
    'weekly-trading-report-push-retry',
    '0 18 * * 6',
    $cron$select private.weekly_report_push_http_dispatch();$cron$
  );
end;
$$;
