import assert from "node:assert/strict"
import { test } from "node:test"
import { storyOwnedStoragePath } from "./storyMediaCleanup.ts"

test("purge only targets story-bucket paths derived from image_url", () => {
  const storyURL =
    "https://example.supabase.co/storage/v1/object/public/stories/u1/abc.jpg"
  const reelURL =
    "https://example.supabase.co/storage/v1/object/public/reels/u1/clip.mp4"
  assert.equal(storyOwnedStoragePath(storyURL), "u1/abc.jpg")
  assert.equal(storyOwnedStoragePath(reelURL), null)
  assert.equal(storyOwnedStoragePath("https://cdn.example/photo.jpg"), null)
})