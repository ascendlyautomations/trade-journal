-- Worker claim lease + service-role-only claim RPC for apple_sign_in_revoke_queue.

alter table public.apple_sign_in_revoke_queue
  add column if not exists lease_expires_at timestamptz;

comment on column public.apple_sign_in_revoke_queue.lease_expires_at is
  'Short-lived claim lease so overlapping cron workers do not process the same row.';

create or replace function public.claim_apple_sign_in_revoke_queue(p_limit integer default 10)
returns setof public.apple_sign_in_revoke_queue
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit, 10), 50));
  v_lease interval := interval '10 minutes';
begin
  return query
  update public.apple_sign_in_revoke_queue q
  set lease_expires_at = timezone('utc', now()) + v_lease
  where q.id in (
    select sq.id
    from public.apple_sign_in_revoke_queue sq
    where sq.next_attempt_at <= timezone('utc', now())
      and (sq.lease_expires_at is null or sq.lease_expires_at < timezone('utc', now()))
    order by sq.next_attempt_at asc, sq.created_at asc
    limit v_limit
    for update skip locked
  )
  returning q.*;
end;
$$;

comment on function public.claim_apple_sign_in_revoke_queue(integer) is
  'Claims due Apple revoke queue rows for background processing (service role only).';

revoke all on function public.claim_apple_sign_in_revoke_queue(integer) from public;
revoke all on function public.claim_apple_sign_in_revoke_queue(integer) from anon;
revoke all on function public.claim_apple_sign_in_revoke_queue(integer) from authenticated;
