import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  profilePostsCountFromSectionCounts,
} from "./profileOverviewExtras.ts"

describe("profilePostsCountFromSectionCounts", () => {
  it("reads profile_posts from bootstrap section_counts", () => {
    assert.equal(
      profilePostsCountFromSectionCounts({
        has_room: false,
        profile_posts: 12,
      } as never),
      12
    )
  })

  it("returns null when profile_posts is absent", () => {
    assert.equal(
      profilePostsCountFromSectionCounts({ has_active_story: true }),
      null
    )
    assert.equal(profilePostsCountFromSectionCounts(null), null)
  })
})
