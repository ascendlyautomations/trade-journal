import assert from "node:assert/strict"
import { test } from "node:test"
import {
  STORY_ACTIVITY_RETENTION_MS,
  storyActivityRetentionCutoffIso,
  storyPublicExpiryCutoffIso,
} from "./storyLifecycle.ts"
import { STORY_PUBLIC_WINDOW_MS } from "./storyLifecycle.ts"

test("retention is 30 days after the public 24h window", () => {
  const now = Date.parse("2026-06-01T12:00:00.000Z")
  const publicCutoff = Date.parse(storyPublicExpiryCutoffIso(now))
  const retentionCutoff = Date.parse(storyActivityRetentionCutoffIso(now))
  assert.equal(now - publicCutoff, STORY_PUBLIC_WINDOW_MS)
  assert.equal(publicCutoff - retentionCutoff, STORY_ACTIVITY_RETENTION_MS)
})