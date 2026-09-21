-- Phase 6D — publish analytical revision signal (user_analytics_state) to Supabase Realtime.
-- Realtime carries revision bumps only; authoritative analytics remain RPC + GRDB.
-- Does NOT publish trades or trade_daily_stats. RLS unchanged (SELECT own row only).

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'user_analytics_state'
    ) then
      alter publication supabase_realtime add table public.user_analytics_state;
    end if;
  end if;
end;
$$;

comment on table public.user_analytics_state is
  'Per-user analytical revision high-water. Realtime (Phase 6D) signals revision advances; clients reconcile via authoritative RPCs.';
