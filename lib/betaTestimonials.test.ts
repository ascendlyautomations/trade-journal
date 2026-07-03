const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  computeUserReviewStats,
  selectFeaturedHomepageReviews,
} = require("./userReviewDisplay.ts")

function row(partial) {
  return {
    title: "Great",
    review: "Love it",
    would_recommend: true,
    featured: false,
    created_at: "2026-01-01T00:00:00Z",
    display_name: "Alex",
    username_snapshot: "alex",
    avatar_snapshot: null,
    ...partial,
  }
}

describe("legacy beta testimonial selectors", () => {
  it("computeUserReviewStats matches legacy expectations", () => {
    const stats = computeUserReviewStats([
      row({ id: "1", rating: 5 }),
      row({ id: "2", rating: 4 }),
    ])
    assert.equal(stats.count, 2)
    assert.equal(stats.averageRating, 4.5)
  })

  it("selectFeaturedHomepageReviews prioritizes featured rows", () => {
    const selected = selectFeaturedHomepageReviews(
      [
        row({ id: "a", rating: 4, featured: false }),
        row({ id: "b", rating: 5, featured: true }),
        row({ id: "c", rating: 3, featured: false }),
      ],
      2
    )
    assert.deepEqual(selected.map((item) => item.id), ["b"])
  })
})
