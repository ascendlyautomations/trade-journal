# Story engagement — production deployment notes

Backend migrations:

- `20261125130000_story_engagement.sql` — likes, views, insights RPC, retention, storage gate, notifications
- `20261125140000_activity_bootstrap_story_id.sql` — `story_id` on activity bootstrap notifications
- `20261125233000_story_engagement_backend_audit.sql` — insights `reply_count`, story-reply index, `story_likes` Realtime (optional if `20261125231500` already applied — prefer `233000` only)

Apply **in order** on staging, then production. Regenerate `lib/database.types.ts` after apply if your workflow requires it.

## Storage security (released clients)

The `stories` bucket remains **public** (`storage.buckets.public = true`). Shipped iOS and web load story media via persisted **`/storage/v1/object/public/stories/...`** URLs in `stories.image_url`.

### What is enforced today

| Layer | Behavior |
|-------|----------|
| Row RLS | Non-owners only `SELECT` stories with `created_at` within 24h (owner sees own rows until metadata purge). |
| Storage SELECT policy | `story_storage_object_readable` — active story must exist for authenticated storage API access. **Does not affect public object URLs while the bucket is public.** |
| Cron `expireStoryMedia` | Force-deletes bucket objects for expired rows (24h–30d retention window); ignores DM URL retention. |
| Owner manual delete | `deleteStoryById` → `purgeStoryStorageAfterStoryRemoval` — same force delete when no other story row shares `image_url`. |

### Public URL exposure window

Until cron removes an object (or the story is manually deleted), **anyone with the URL** can fetch story bytes from the public bucket. Typical maximum lag: **up to ~24 hours** after the story leaves the public viewing window, because Vercel cron runs **once daily** (`15 7 * * *` in `vercel.json`).

DM and share payloads may still contain the old URL string; after object deletion, fetches fail (clients should show “Story expired” when UI ships).

### Cron frequency (Vercel)

- **Hobby / most plans:** cron invocations are limited; daily runs are the practical default.
- **Pro / Enterprise:** can schedule more often (e.g. `15 7,19 * * *` for twice daily, or hourly on supported tiers).

Increasing frequency reduces public URL exposure but does not replace a private bucket + signed URLs.

**Do not** set the bucket private without a coordinated client release (see below).

## Future: private bucket + signed URLs (backward compatible)

Recommended phased cutover:

1. **Dual-publish (server):** continue writing `image_url` public URLs; add optional `stories_media_path` or derive path from URL; serve new uploads via signed URL helper for *new* clients only.
2. **Client cutover:** iOS `MediaURLResolver` and web `StorageImage` — if path-only or signed URL present, use `createSignedUrl` / authenticated fetch; else fall back to legacy `image_url` (old app versions).
3. **Flip bucket:** `update storage.buckets set public = false where id = 'stories'`; keep `stories_storage_select` + active-story gate.
4. **Retire public URLs:** stop storing `/object/public/` in new rows; migrate or leave historical JSON in DMs unchanged.

## Notification durability

- Story like rows use `notifications.story_id` (FK **ON DELETE SET NULL**).
- Insert path sets `content` JSON: `{ "kind": "story", "story_id": "..." }`.
- `stories_preserve_like_notifications` (BEFORE DELETE on `stories`) merges `story_unavailable: true` into `content` before row purge at end of retention.
- Activity bootstrap and web notification list now include optional `story_id`; routing UI is not implemented yet.

## Owner activity retention

- **0–24h:** public story window (non-owner visibility + engagement).
- **After 24h:** stories leave public surfaces; owners retain indefinite **Story Archive** (metadata, media, insights) until explicit delete. See `docs/STORY_ARCHIVE_STORAGE_MIGRATION.md` and migration `20261127183000_story_archive_private_storage.sql`.

## Verification checklist (staging)

1. Run `supabase/verification/story_engagement_authorization.sql`.
2. Like a story → one notification with `story_id` + `content`; duplicate like deduped.
3. Unlike → notification removed (`sync_delete_like_notification`).
4. Owner `rpc_v1_story_insights` returns counts; non-owner forbidden.
5. After manual story delete, storage object gone; **other stories’ objects unchanged**.
6. `rpc_v1_activity_bootstrap` JSON notifications include `story_id` when set.
7. Cron smoke: `GET /api/cron/expired-stories` with `CRON_SECRET` returns `expiredMediaStoryCount`, `deletedStorageObjects`, `purgedMetadataRows`.

## Unchanged product behavior (released builds)

- Story publish, feed/profile bootstrap, viewer, share, and reply flows are unchanged.
- No new UI or navigation for story likes / activity sheet.