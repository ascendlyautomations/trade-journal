/** Matches `lib/activeStories.ts` `STORY_WINDOW_MS`. */
export const STORY_PUBLIC_WINDOW_MS = 24 * 60 * 60 * 1000

/** Owner-only activity rows are kept this long after the 24h public window ends. */
export const STORY_ACTIVITY_RETENTION_MS = 30 * 24 * 60 * 60 * 1000

/** Cutoff before which a story has left the public 24h window. */
export function storyPublicExpiryCutoffIso(nowMs = Date.now()): string {
  return new Date(nowMs - STORY_PUBLIC_WINDOW_MS).toISOString()
}

/** Cutoff before which owner metadata rows may be purged (24h + 30d after publish). */
export function storyActivityRetentionCutoffIso(nowMs = Date.now()): string {
  return new Date(
    nowMs - STORY_PUBLIC_WINDOW_MS - STORY_ACTIVITY_RETENTION_MS
  ).toISOString()
}