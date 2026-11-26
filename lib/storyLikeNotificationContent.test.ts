import assert from "node:assert/strict"
import { test } from "node:test"
import {
  buildStoryLikeNotificationContent,
  parseStoryLikeNotificationContent,
} from "./storyLikeNotificationContent.ts"

test("build and parse story like notification content", () => {
  const raw = buildStoryLikeNotificationContent("story-uuid")
  assert.equal(
    parseStoryLikeNotificationContent(raw)?.story_id,
    "story-uuid"
  )
})

test("story like insert row includes durable content", () => {
  const content = buildStoryLikeNotificationContent("story-1")
  const row = {
    user_id: "owner-1",
    sender_id: "liker-1",
    type: "like",
    story_id: "story-1",
    content,
  }
  assert.equal(row.story_id, "story-1")
  assert.equal(parseStoryLikeNotificationContent(row.content)?.story_id, "story-1")
})

test("parse marks unavailable snapshots", () => {
  const raw = JSON.stringify({
    kind: "story",
    story_id: "story-uuid",
    story_unavailable: true,
  })
  const parsed = parseStoryLikeNotificationContent(raw)
  assert.equal(parsed?.story_unavailable, true)
})