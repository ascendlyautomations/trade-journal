-- Enable Supabase Realtime for reel_likes (cross-viewer like count sync).

alter table public.reel_likes replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.reel_likes;
  end if;
exception
  when duplicate_object then null;
end $$;
