-- Allow anonymous visitors to read public achievements (SEO profile pages, explore logged out).
-- Mirrors trades_select_public: anon may only read rows with is_public = true.

drop policy if exists "achievements_select_public" on public.achievements;

create policy "achievements_select_public"
  on public.achievements
  for select
  to anon, authenticated
  using (coalesce(is_public, false) = true);

grant select on table public.achievements to anon;
