-- Fix 42501 on rpc_v1_session_bootstrap after 20261126153000_ios_native_onboarding_persistence.
-- profiles uses column-level SELECT (20261001073000); new iOS columns were not granted.
-- That migration also reverted the stripe_customer_id safe read; restore it (stay SECURITY INVOKER).

grant select (
  ios_contextual_tour_dismissed_version,
  ios_post_onboarding_plan_acknowledged_at
) on table public.profiles to anon, authenticated;

do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_session_bootstrap'
    and pg_get_function_identity_arguments(p.oid) = '';

  if src is null then
    raise exception 'rpc_v1_session_bootstrap() was not found';
  end if;

  if position('security definer' in lower(src)) > 0 then
    raise exception 'rpc_v1_session_bootstrap must stay security invoker';
  end if;

  updated := replace(
    src,
    $old$'stripe_customer_id', p.stripe_customer_id$old$,
    $new$'stripe_customer_id', (select public.profile_owner_private_fields() ->> 'stripe_customer_id')$new$
  );

  if updated <> src then
    execute updated;
  end if;
end
$mig$;