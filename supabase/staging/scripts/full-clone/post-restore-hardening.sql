-- Staging-only: reduce outbound side effects after full production clone.
-- Review output; some statements may no-op on empty cron catalog.
\set ON_ERROR_STOP on

-- Broker auto-sync: stop scheduled pulls against copied tokens.
update public.broker_integration_account_sync
set auto_sync_enabled = false
where auto_sync_enabled is true;

update public.broker_integration_connections
set listener_status = 'stopped'
where listener_status is distinct from 'stopped';

-- Unschedule pg_cron jobs if extension exists (Supabase clone doc recommendation).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobid is not null;
  end if;
exception
  when undefined_table or undefined_function then
    null;
end $$;

select 'post_restore_hardening applied' as result;
