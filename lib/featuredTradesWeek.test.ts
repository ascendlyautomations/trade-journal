const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  getFeaturedWeekStartIso,
  isPublicDiscoverableTradeRow,
  pickBestPnlPost,
  pickHighestRrPost,
} = require("./featuredTradesWeekLogic.ts")

describe("featuredTradesWeek", () => {
  it("getFeaturedWeekStartIso uses a rolling 7-day window", () => {
    const now = new Date("2026-07-03T16:00:00.000Z")
    const start = new Date(getFeaturedWeekStartIso(now))
    const diffDays = (now.getTime() - start.getTime()) / (1000 * 60 * 60 * 24)
    assert.ok(Math.abs(diffDays - 7) < 0.01)
  })

  it("isPublicDiscoverableTradeRow requires public trade and public profile", () => {
    assert.equal(
      isPublicDiscoverableTradeRow({
        trades: { is_public: true },
        profiles: { is_private: false },
      }),
      true
    )
    assert.equal(
      isPublicDiscoverableTradeRow({
        trades: { is_public: true },
        profiles: { is_private: true },
      }),
      false
    )
    assert.equal(
      isPublicDiscoverableTradeRow({
        trades: { is_public: false },
        profiles: { is_private: false },
      }),
      false
    )
  })

  it("pickBestPnlPost chooses highest pnl and breaks ties by recency", () => {
    const rows = [
      { id: "a", pnl: 100, created_at: "2026-07-01T10:00:00.000Z" },
      { id: "b", pnl: 250, created_at: "2026-07-02T10:00:00.000Z" },
      { id: "c", pnl: 250, created_at: "2026-07-03T10:00:00.000Z" },
    ]
    assert.equal(pickBestPnlPost(rows)?.id, "c")
  })

  it("pickHighestRrPost chooses highest rr and breaks ties by recency", () => {
    const rows = [
      { id: "a", rr: 1.5, created_at: "2026-07-01T10:00:00.000Z" },
      { id: "b", rr: 3, created_at: "2026-07-02T10:00:00.000Z" },
      { id: "c", rr: 3, created_at: "2026-07-03T10:00:00.000Z" },
    ]
    assert.equal(pickHighestRrPost(rows)?.id, "c")
  })

  it("pickHighestRrPost ignores blank or invalid rr", () => {
    const rows = [
      { id: "a", rr: null, created_at: "2026-07-03T10:00:00.000Z" },
      { id: "b", rr: "", created_at: "2026-07-03T11:00:00.000Z" },
      { id: "c", rr: 2, created_at: "2026-07-01T10:00:00.000Z" },
    ]
    assert.equal(pickHighestRrPost(rows)?.id, "c")
  })
})
