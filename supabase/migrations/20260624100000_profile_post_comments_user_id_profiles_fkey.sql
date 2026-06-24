-- PostgREST profiles(...) embed on profile_post_comments requires user_id -> profiles.id.

alter table public.profile_post_comments
  drop constraint if exists profile_post_comments_user_id_fkey;

alter table public.profile_post_comments
  add constraint profile_post_comments_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;
