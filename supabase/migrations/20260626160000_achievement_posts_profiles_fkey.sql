-- PostgREST profiles(...) embed on achievement_posts and achievement_post_comments
-- requires user_id -> profiles.id (same fix as profile_post_comments).

alter table public.achievement_posts
  drop constraint if exists achievement_posts_user_id_fkey;

alter table public.achievement_posts
  add constraint achievement_posts_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

alter table public.achievement_post_comments
  drop constraint if exists achievement_post_comments_user_id_fkey;

alter table public.achievement_post_comments
  add constraint achievement_post_comments_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;
