# Story archive — storage migration (run separately from SQL migration)

Apply `supabase/migrations/20261127183000_story_archive_private_storage.sql` on staging, then production.

## What changes

1. The `stories` bucket is set to **private** (`storage.buckets.public = false`).
2. Automatic cron media deletion and 30-day metadata purge are **disabled in app code** (cron route becomes a no-op).
3. New uploads store the **object path** in `stories.storage_path` and `stories.image_url` (no `/object/public/` URL).

## Operator checklist

1. **Deploy clients** that resolve story media via `createSignedUrl` (web + iOS in this release) before or with the migration.
2. **Verify bucket privacy** in Supabase Dashboard → Storage → stories → Public: **off**.
3. **Optional backfill** (already in SQL): `storage_path` populated from legacy `image_url` paths; objects remain at the same paths.
4. **Legacy public URLs** in old DM JSON may still contain `/object/public/stories/...` strings — clients extract the path and request signed URLs. Objects must still exist (cron no longer deletes them).
5. **Smoke test**
   - Publish a story → view in feed (< 24h) as follower.
   - After expiry (or test clock) → owner opens Settings → Story Archive → playback.
   - Non-owner DM reply → compact “Story unavailable”, no media fetch.
   - Owner opens archived story from DM reply.
   - Delete story from archive → storage object removed (`deleteStoryById`).

## Rollback (emergency only)

- Re-enable `storage.buckets.public = true` **only** if you must ship hotfix clients that still use public URLs (not recommended).
- Do not re-enable `purgeExpiredStories` without product sign-off.

## Cron

`/api/cron/expired-stories` returns success with zero work. You may remove the Vercel schedule later; keeping it is harmless.