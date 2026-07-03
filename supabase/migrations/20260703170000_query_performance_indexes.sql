-- Sprint #7: indexes for high-frequency query patterns (messages, trades, achievements).

-- Backtest lab: filter by user + mode, order by created_at.
create index if not exists trades_user_id_mode_created_at_idx
  on public.trades (user_id, created_at desc)
  where mode = 'backtest';

-- Profile public trade grids (user_id + is_public filter, created_at sort).
create index if not exists trades_user_id_public_created_at_idx
  on public.trades (user_id, created_at desc)
  where is_public = true;

-- Explore / leaderboard: global public trades within time windows.
create index if not exists trades_public_created_at_idx
  on public.trades (created_at desc)
  where is_public = true;

-- Achievements list ordering (own page + profile tab).
create index if not exists achievements_user_id_list_idx
  on public.achievements (
    user_id,
    is_featured desc,
    achieved_at desc nulls last,
    sort_order asc nulls last
  );

-- Messages inbox: participant lookup by user.
create index if not exists conversation_participants_user_id_idx
  on public.conversation_participants (user_id);

-- Messages inbox + thread header: participants by conversation.
create index if not exists conversation_participants_conversation_id_idx
  on public.conversation_participants (conversation_id);

-- DM thread load (ordered history).
create index if not exists messages_conversation_id_created_at_idx
  on public.messages (conversation_id, created_at asc);

-- Unread badge scan per conversation (sender filter).
create index if not exists messages_conversation_sender_idx
  on public.messages (conversation_id, sender_id)
  where sender_id is not null;

-- Streak milestone counts: comments by author.
create index if not exists comments_user_id_idx
  on public.comments (user_id);

-- Streak milestone counts: feed posts by author.
create index if not exists posts_user_id_idx
  on public.posts (user_id);
