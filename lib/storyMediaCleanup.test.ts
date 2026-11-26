import assert from "node:assert/strict"
import { test } from "node:test"
import {
  planStoryMediaDeletion,
  storyOwnedStoragePath,
} from "./storyMediaCleanup.ts"

const storyURL =
  "https://example.supabase.co/storage/v1/object/public/stories/user-1/clip.jpg"
const reelURL =
  "https://example.supabase.co/storage/v1/object/public/reels/user-1/clip.mp4"

test("story storage paths stay inside the stories bucket", () => {
  assert.equal(storyOwnedStoragePath(storyURL), "user-1/clip.jpg")
  assert.equal(storyOwnedStoragePath(reelURL), null)
  assert.equal(storyOwnedStoragePath("https://cdn.example/photo.jpg"), null)
  assert.equal(
    storyOwnedStoragePath(
      "https://example.supabase.co/storage/v1/object/public/stories/user-1/../secrets.jpg"
    ),
    null
  )
})

test("shared reference retention applies only to unshared cleanup planner", () => {
  const plan = planStoryMediaDeletion({
    stories: [
      { id: "expired-own", image_url: storyURL },
      { id: "expired-shared", image_url: storyURL },
    ],
    retainedMediaURLs: [storyURL],
  })

  assert.deepEqual(plan.storagePaths, [])
})

test("unshared story objects are eligible for deletion", () => {
  const owned =
    "https://example.supabase.co/storage/v1/object/public/stories/user-2/a.jpg"
  const plan = planStoryMediaDeletion({
    stories: [{ id: "gone", image_url: owned }],
    retainedMediaURLs: [],
  })
  assert.deepEqual(plan.storagePaths, ["user-2/a.jpg"])
})

