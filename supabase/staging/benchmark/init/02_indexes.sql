create index posts_user_id_created_at_idx on public.posts (user_id, created_at desc);
create index posts_created_at_idx on public.posts (created_at desc);
create index profile_posts_user_id_created_at_idx
  on public.profile_posts (user_id, created_at desc, id desc);
create index achievement_posts_user_id_created_at_idx
  on public.achievement_posts (user_id, created_at desc);
create index achievement_posts_created_at_idx on public.achievement_posts (created_at desc);
create index reels_user_id_created_at_idx on public.reels (user_id, created_at desc);
create index reels_created_at_idx on public.reels (created_at desc);
create index followers_pair_unique_idx on public.followers (follower_id, following_id);
create index user_blocks_blocker_id_idx on public.user_blocks (blocker_id);
