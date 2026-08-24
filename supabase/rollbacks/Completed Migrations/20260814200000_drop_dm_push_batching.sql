-- Phase 4: remove Direct Message custom push batching.
-- APNs collapse-id / thread-id replace push_batch_windows for DMs.
-- like/follow/room_digest batching also has no remaining app writers.

drop function if exists public.bump_dm_push_batch(uuid, text, jsonb, timestamptz);

delete from public.push_batch_windows
where batch_kind = 'dm';

-- Entire table is unused by the application (no TS/Swift writers remain).
drop index if exists public.push_batch_windows_due_idx;
drop table if exists public.push_batch_windows;
