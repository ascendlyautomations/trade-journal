import { test } from "node:test"
import { optimizeStorageImageUrl } from "./optimizedStorageImage.ts"
import assert from "node:assert/strict"

const SAMPLE =
  "https://example.supabase.co/storage/v1/object/public/trades/abc/screenshot.png"

test("feed-thumb and profile trade cards share one transform URL", () => {
  const feedUrl = optimizeStorageImageUrl(SAMPLE, "feed-thumb")
  assert.ok(feedUrl)
  assert.match(feedUrl, /width=640/)
  assert.match(feedUrl, /quality=75/)
  assert.doesNotMatch(feedUrl, /width=800/)
  assert.doesNotMatch(feedUrl, /resize=/)
})

test("feed cards resize with contain and do not cover-crop", () => {
  const cardUrl = optimizeStorageImageUrl(SAMPLE, "feed-card")
  assert.ok(cardUrl)
  assert.match(cardUrl, /width=1440/)
  assert.match(cardUrl, /height=1080/)
  assert.match(cardUrl, /resize=contain/)
  assert.match(cardUrl, /quality=75/)
  assert.doesNotMatch(cardUrl, /resize=cover/)

  const detailUrl = optimizeStorageImageUrl(SAMPLE, "feed-detail")
  assert.ok(detailUrl)
  assert.match(detailUrl, /width=1280/)
  assert.doesNotMatch(detailUrl, /resize=/)
  assert.doesNotMatch(detailUrl, /height=/)
})

test("achievement gallery cards contain the full image", () => {
  const cardUrl = optimizeStorageImageUrl(SAMPLE, "achievement-card")
  assert.ok(cardUrl)
  assert.match(cardUrl, /width=960/)
  assert.match(cardUrl, /height=720/)
  assert.match(cardUrl, /resize=contain/)
  assert.doesNotMatch(cardUrl, /resize=cover/)

  const detailUrl = optimizeStorageImageUrl(SAMPLE, "feed-detail")
  assert.ok(detailUrl)
  assert.match(detailUrl, /width=1280/)
  assert.doesNotMatch(detailUrl, /resize=/)
})

test("feed-thumb URL is stable for browser cache reuse", () => {
  const first = optimizeStorageImageUrl(SAMPLE, "feed-thumb")
  const second = optimizeStorageImageUrl(SAMPLE, "feed-thumb")
  assert.equal(first, second)
})
export {}
