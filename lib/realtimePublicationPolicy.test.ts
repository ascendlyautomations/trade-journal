import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import {
  REALTIME_POSTGRES_CHANGES_DISABLED_TABLES,
  REALTIME_PUBLICATION_CANDIDATE_TABLES,
  isPostgresChangesWatchEnabled,
} from "./realtimePublicationPolicy.ts"

test("ineffective watches are disabled and are not also publication candidates", () => {
  for (const table of [
    "stories",
    "profile_post_likes",
    "achievement_post_likes",
  ]) {
    assert.equal(isPostgresChangesWatchEnabled(table), false)
    assert.equal(
      REALTIME_PUBLICATION_CANDIDATE_TABLES.includes(
        table as (typeof REALTIME_PUBLICATION_CANDIDATE_TABLES)[number]
      ),
      false
    )
    assert.equal(REALTIME_POSTGRES_CHANGES_DISABLED_TABLES.has(table), true)
  }
})

test("published social tables remain enabled", () => {
  assert.equal(isPostgresChangesWatchEnabled("reel_likes"), true)
  assert.equal(isPostgresChangesWatchEnabled("trade_likes"), true)
  assert.equal(isPostgresChangesWatchEnabled("likes"), true)
  assert.equal(isPostgresChangesWatchEnabled("messages"), true)
  assert.equal(isPostgresChangesWatchEnabled("room_messages"), true)
})

test("read-cursor and room membership watches stay publication candidates", () => {
  assert.deepEqual(
    [...REALTIME_PUBLICATION_CANDIDATE_TABLES],
    ["conversation_member_preferences", "room_members"]
  )
  for (const table of REALTIME_PUBLICATION_CANDIDATE_TABLES) {
    assert.equal(isPostgresChangesWatchEnabled(table), true)
  }
})

test("active stories hook does not open a stories postgres_changes watch", () => {
  const src = readFileSync(new URL("./useActiveStories.ts", import.meta.url), "utf8")
  assert.match(src, /fetchActiveStoriesForUserIds/)
  assert.match(src, /pruneExpiredStories/)
  assert.doesNotMatch(src, /supabase\.channel\(/)
  assert.doesNotMatch(src, /\.on\(\s*["']postgres_changes["']/)
  assert.doesNotMatch(src, /table:\s*["']stories["']/)
})
