-- Dashboard chart helpers are SECURITY INVOKER and pass the whole trades row
-- into analytics_dashboard_trade_in_scope(trades), and distributions also
-- selects t.*. After table SELECT was revoked, that raises 42501. Headline
-- metrics stay populated because they read trade_daily_stats.
--
-- These helpers accept a user id, so they become SECURITY DEFINER only with
-- an auth.uid() ownership predicate. A caller cannot read another user's
-- journal analytics. No table SELECT grant. RLS stays enabled. Direct
-- column privileges are unchanged.

do $mig$
declare
  fn text;
  src text;
  updated text;
  fns text[] := array[
    'analytics_dashboard_equity_block',
    'analytics_dashboard_distributions_block',
    'analytics_dashboard_insights_block',
    'analytics_dashboard_streak_snapshot'
  ];
begin
  foreach fn in array fns loop
    select pg_get_functiondef(p.oid) into src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = fn
      and pg_get_function_identity_arguments(p.oid) =
        'p_user_id uuid, p_start date, p_end date, p_account_id uuid';

    if src is null then
      raise exception '%(uuid, date, date, uuid) was not found', fn;
    end if;

    if position('auth.uid() is not distinct from p_user_id' in src) = 0 then
      if position('where t.user_id = p_user_id' in src) = 0 then
        raise exception '% trade owner predicate was not found', fn;
      end if;
      updated := replace(
        src,
        'where t.user_id = p_user_id',
        'where t.user_id = p_user_id and auth.uid() is not distinct from p_user_id'
      );
      execute updated;
    end if;

    execute format(
      'alter function public.%I(uuid, date, date, uuid) security definer',
      fn
    );
    execute format(
      'alter function public.%I(uuid, date, date, uuid) set search_path = public, pg_temp',
      fn
    );
    execute format(
      'revoke all on function public.%I(uuid, date, date, uuid) from public, anon',
      fn
    );
    execute format(
      'grant execute on function public.%I(uuid, date, date, uuid) to authenticated',
      fn
    );
  end loop;
end
$mig$;
