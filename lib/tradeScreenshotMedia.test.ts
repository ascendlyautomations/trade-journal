import { test } from "node:test"
import { optimizeStorageImageUrl } from "./optimizedStorageImage.ts"
import assert from "node:assert/strict"
import { assertNoSupabaseStorageTransformUrl } from "./supabaseStorageTransformGuard.ts"

const SAMPLE =
  "https://example.supabase.co/storage/v1/object/public/trades/abc/screenshot.png"

test("feed-thumb and profile trade cards use object URLs only", () => {
  const feedUrl = optimizeStorageImageUrl(SAMPLE, "feed-thumb")
  assert.ok(feedUrl)
  assert.match(feedUrl, /\/storage\/v1\/object\/public\//)
  assertNoSupabaseStorageTransformUrl(feedUrl!)
  assert.doesNotMatch(feedUrl!, /width=/)
  assert.doesNotMatch(feedUrl!, /resize=/)
})

test("feed cards use object URLs without transform query params", () => {
  const cardUrl = optimizeStorageImageUrl(SAMPLE, "feed-card")
  assert.ok(cardUrl)
  assertNoSupabaseStorageTransformUrl(cardUrl!)
  assert.doesNotMatch(cardUrl!, /width=/)
  assert.doesNotMatch(cardUrl!, /resize=/)

  const detailUrl = optimizeStorageImageUrl(SAMPLE, "feed-detail")
  assert.ok(detailUrl)
  assertNoSupabaseStorageTransformUrl(detailUrl!)
  assert.doesNotMatch(detailUrl!, /width=/)
})

test("achievement gallery cards use object URLs only", () => {
  const cardUrl = optimizeStorageImageUrl(SAMPLE, "achievement-card")
  assert.ok(cardUrl)
  assertNoSupabaseStorageTransformUrl(cardUrl!)
  assert.doesNotMatch(cardUrl!, /resize=/)

  const detailUrl = optimizeStorageImageUrl(SAMPLE, "feed-detail")
  assert.ok(detailUrl)
  assertNoSupabaseStorageTransformUrl(detailUrl!)
})

test("feed-thumb URL is stable for browser cache reuse", () => {
  const first = optimizeStorageImageUrl(SAMPLE, "feed-thumb")
  const second = optimizeStorageImageUrl(SAMPLE, "feed-thumb")
  assert.equal(first, second)
})
export {}
