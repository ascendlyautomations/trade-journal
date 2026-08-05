-- Phase 3 Disk IO: material indexes for remaining hot paths after Phases 1–2.
-- Skipped (already covered or redundant):
--   likes(post_id) via likes_post_user_unique_idx
--   comment_likes(comment_id) via comment_likes_lookup_idx
--   trade_likes(trade_id) via trade_likes_trade_id_idx
--   messages/room_messages cursor indexes (phase1 messaging)
--   notifications(user_id) where read=false (navbar unread)
--   trades(created_at desc) where is_public (existing; ASC scans reverse)

-- Feed engagement + comment threads: eq/in post_id, order created_at
create index if not exists comments_post_id_created_at_idx
  on public.comments (post_id, created_at);

-- Follower counts / lists (unique index is follower_id-leading only)
create index if not exists followers_following_id_created_at_idx
  on public.followers (following_id, created_at desc);

-- Notifications inbox: eq user_id, order created_at desc
create index if not exists notifications_user_id_created_at_idx
  on public.notifications (user_id, created_at desc);

-- Profile feed posts: eq user_id, order created_at desc
create index if not exists posts_user_id_created_at_idx
  on public.posts (user_id, created_at desc);

-- Global trade feed: order created_at desc (no user filter)
create index if not exists posts_created_at_idx
  on public.posts (created_at desc);
