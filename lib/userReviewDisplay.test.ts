import { describe, it } from "node:test"
import { computeUserReviewStats, resolvePublicReviewAvatar, selectFeaturedHomepageReviews, type PublicUserReview, } from "./userReviewDisplay.ts"
import assert from "node:assert/strict"

function row(
  partial: Partial<PublicUserReview> & Pick<PublicUserReview, "id">
): PublicUserReview {
  return {
    title: "Great",
    review: "Love it",
    would_recommend: true,
    featured: false,
    created_at: "2026-01-01T00:00:00Z",
    display_name: "Alex",
    username_snapshot: "alex",
    avatar_snapshot: null,
    rating: 5,
    ...partial,
  }
}

describe("computeUserReviewStats", () => {
  it("returns zero stats for empty list", () => {
    assert.deepEqual(computeUserReviewStats([]), {
      averageRating: 0,
      count: 0,
    })
  })

  it("computes average to one decimal", () => {
    const stats = computeUserReviewStats([
      row({ id: "1", rating: 5 }),
      row({ id: "2", rating: 4 }),
    ])
    assert.equal(stats.count, 2)
    assert.equal(stats.averageRating, 4.5)
  })
})

describe("selectFeaturedHomepageReviews", () => {
  it("returns only featured reviews newest first", () => {
    const selected = selectFeaturedHomepageReviews(
      [
        row({ id: "a", rating: 4, featured: false }),
        row({ id: "b", rating: 5, featured: true, created_at: "2026-01-02T00:00:00Z" }),
        row({ id: "c", rating: 3, featured: true, created_at: "2026-01-03T00:00:00Z" }),
        row({ id: "d", rating: 5, featured: false }),
      ],
      2
    )
    assert.deepEqual(selected.map((item) => item.id), ["c", "b"])
  })
})

describe("resolvePublicReviewAvatar", () => {
  it("returns trimmed snapshot when present", () => {
    assert.equal(
      resolvePublicReviewAvatar(
        row({ id: "1", avatar_snapshot: "  https://example.com/a.png  " })
      ),
      "https://example.com/a.png"
    )
  })

  it("returns null when snapshot is empty", () => {
    assert.equal(resolvePublicReviewAvatar(row({ id: "1", avatar_snapshot: "  " })), null)
    assert.equal(resolvePublicReviewAvatar(row({ id: "1", avatar_snapshot: null })), null)
  })
})
export {}
