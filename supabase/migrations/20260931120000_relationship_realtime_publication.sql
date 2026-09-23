-- Phase 10E — viewer-scoped relationship Realtime (followers + follow_requests).
-- RLS unchanged; clients subscribe with follower_id / following_id / requester_id / target_id filters.

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'followers'
    ) then
      alter publication supabase_realtime add table public.followers;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'follow_requests'
    ) then
      alter publication supabase_realtime add table public.follow_requests;
    end if;
  end if;
end $$;

alter table public.followers replica identity full;
alter table public.follow_requests replica identity full;
