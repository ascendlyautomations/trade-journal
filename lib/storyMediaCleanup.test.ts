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

test("expired story rows are deleted while shared media is kept", () => {
  const plan = planStoryMediaDeletion({
    stories: [
      { id: "expired-own", image_url: storyURL },
      { id: "expired-shared", image_url: storyURL },
      { id: "expired-reel-url", image_url: reelURL },
      { id: "expired-external", image_url: "https://cdn.example/photo.jpg" },
    ],
    retainedMediaURLs: [storyURL],
  })

  assert.deepEqual(plan.storyIDs, [
    "expired-own",
    "expired-shared",
    "expired-reel-url",
    "expired-external",
  ])
  assert.deepEqual(plan.storagePaths, [])
})

test("unshared story objects are the only storage deletions", () => {
  const owned =
    "https://example.supabase.co/storage/v1/object/public/stories/user-2/a.jpg"
  const plan = planStoryMediaDeletion({
    stories: [
      { id: "gone", image_url: owned },
      { id: "other", image_url: reelURL },
    ],
    retainedMediaURLs: [],
  })
  assert.deepEqual(plan.storagePaths, ["user-2/a.jpg"])
})
