-- Phase 10D — Feed/Profile entity Realtime (posts, profile_posts, trades, reels, achievement_posts).

alter table public.posts replica identity full;
alter table public.profile_posts replica identity full;
alter table public.trades replica identity full;
alter table public.reels replica identity full;
alter table public.achievement_posts replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.posts;
    alter publication supabase_realtime add table public.profile_posts;
    alter publication supabase_realtime add table public.trades;
    alter publication supabase_realtime add table public.reels;
    alter publication supabase_realtime add table public.achievement_posts;
  end if;
exception
  when duplicate_object then null;
end $$;
