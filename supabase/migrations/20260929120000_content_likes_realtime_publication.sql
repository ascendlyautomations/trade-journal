-- Phase 10C — incremental content engagement Realtime (likes only).

alter table public.trade_likes replica identity full;
alter table public.profile_post_likes replica identity full;
alter table public.achievement_post_likes replica identity full;
alter table public.likes replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.trade_likes;
    alter publication supabase_realtime add table public.profile_post_likes;
    alter publication supabase_realtime add table public.achievement_post_likes;
    alter publication supabase_realtime add table public.likes;
  end if;
exception
  when duplicate_object then null;
end $$;
