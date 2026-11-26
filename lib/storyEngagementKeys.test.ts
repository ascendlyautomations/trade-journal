import assert from "node:assert/strict"
import { test } from "node:test"

/** Mirrors notificationsDisplay.engagementGroupKey story branch. */
function storyLikeGroupKey(storyId: string | null): string | null {
  if (storyId) return `story:${storyId}`
  return null
}

test("story like notifications group on story_id", () => {
  assert.equal(storyLikeGroupKey("story-1"), "story:story-1")
  assert.equal(storyLikeGroupKey(null), null)
})