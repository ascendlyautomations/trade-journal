-- Tear down Platform Updates Supabase cron wake (if 20260929180000 was applied).
-- Safe no-op when the job/function never existed.

do $$
declare
  existing_job_id bigint;
begin
  for existing_job_id in
    select jobid from cron.job where jobname = 'platform_updates_vercel_wake'
  loop
    perform cron.unschedule(existing_job_id);
  end loop;
exception
  when undefined_table then
    null;
end $$;

drop function if exists public.platform_updates_invoke_vercel_cron();
