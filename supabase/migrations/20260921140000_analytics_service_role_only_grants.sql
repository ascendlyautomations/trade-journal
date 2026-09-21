-- Phase 1C: Supabase default grants EXECUTE to authenticated; restrict rebuild/backfill to service_role.

revoke all on function public.rebuild_trade_daily_stats_for_user(uuid) from public, anon, authenticated;
grant execute on function public.rebuild_trade_daily_stats_for_user(uuid) to service_role;

revoke all on function public.rebuild_trade_daily_stats_for_account(uuid, uuid) from public, anon, authenticated;
grant execute on function public.rebuild_trade_daily_stats_for_account(uuid, uuid) to service_role;

revoke all on function public.backfill_trade_daily_stats_batch(integer) from public, anon, authenticated;
grant execute on function public.backfill_trade_daily_stats_batch(integer) to service_role;

revoke all on function public.analytics_raw_normal_range_metrics(uuid, date, date, uuid, text) from public, anon, authenticated;
grant execute on function public.analytics_raw_normal_range_metrics(uuid, date, date, uuid, text) to service_role;
