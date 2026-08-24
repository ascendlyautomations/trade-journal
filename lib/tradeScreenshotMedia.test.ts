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

test("feed-thumb URL is stable for browser cache reuse", () => {
  const first = optimizeStorageImageUrl(SAMPLE, "feed-thumb")
  const second = optimizeStorageImageUrl(SAMPLE, "feed-thumb")
  assert.equal(first, second)
})
export {}
