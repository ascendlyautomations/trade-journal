const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  computeBetaTestimonialStats,
  selectHomepageTestimonials,
} = require("./betaTestimonialDisplay.ts")

function row(partial) {
  return {
    title: "Great",
    review: "Love it",
    pros: null,
    cons: null,
    would_recommend: true,
    featured: false,
    created_at: "2026-01-01T00:00:00Z",
    username: "trader",
    avatar_url: null,
    trading_style: null,
    trader_type: null,
    started_trading: null,
    ...partial,
  }
}

describe("computeBetaTestimonialStats", () => {
  it("returns zero stats for empty list", () => {
    assert.deepEqual(computeBetaTestimonialStats([]), {
      averageRating: 0,
      count: 0,
    })
  })

  it("computes average to one decimal", () => {
    const stats = computeBetaTestimonialStats([
      row({ id: "1", rating: 5 }),
      row({ id: "2", rating: 4 }),
    ])
    assert.equal(stats.count, 2)
    assert.equal(stats.averageRating, 4.5)
  })
})

describe("selectHomepageTestimonials", () => {
  it("prioritizes featured testimonials", () => {
    const selected = selectHomepageTestimonials(
      [
        row({ id: "a", rating: 4, featured: false }),
        row({ id: "b", rating: 5, featured: true }),
        row({ id: "c", rating: 3, featured: false }),
      ],
      2
    )
    assert.deepEqual(selected.map((item) => item.id), ["b", "a"])
  })
})
