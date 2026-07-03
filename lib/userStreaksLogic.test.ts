const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  areConsecutiveWeekdays,
  computeWeekdayActivityStreak,
  computeWinningTradeStreak,
  nextWeekdayDateKey,
  parseLocalDateKey,
  resolveNextMilestone,
} = require("./userStreaksLogic.ts")

describe("userStreaksLogic", () => {
  it("nextWeekdayDateKey skips weekends", () => {
    assert.equal(nextWeekdayDateKey("2026-07-03"), "2026-07-06")
  })

  it("areConsecutiveWeekdays links Friday to Monday", () => {
    assert.equal(areConsecutiveWeekdays("2026-07-03", "2026-07-06"), true)
    assert.equal(areConsecutiveWeekdays("2026-07-03", "2026-07-07"), false)
  })

  it("computeWeekdayActivityStreak ignores weekends in the active set", () => {
    const today = parseLocalDateKey("2026-07-08")
    const { current, longest } = computeWeekdayActivityStreak(
      ["2026-07-06", "2026-07-07", "2026-07-08", "2026-07-04"],
      today
    )
    assert.equal(current, 3)
    assert.equal(longest, 3)
  })

  it("computeWeekdayActivityStreak does not break across weekends", () => {
    const { current } = computeWeekdayActivityStreak(
      ["2026-07-03", "2026-07-06"],
      parseLocalDateKey("2026-07-06")
    )
    assert.equal(current, 2)
  })

  it("computeWinningTradeStreak ignores break-even trades", () => {
    const trades = [
      { pnl: 100, created_at: "2026-07-01T10:00:00Z" },
      { pnl: 0, created_at: "2026-07-02T10:00:00Z" },
      { pnl: 50, created_at: "2026-07-03T10:00:00Z" },
      { pnl: -20, created_at: "2026-07-04T10:00:00Z" },
      { pnl: 30, created_at: "2026-07-05T10:00:00Z" },
    ]
    const { current, longest } = computeWinningTradeStreak(trades)
    assert.equal(longest, 2)
    assert.equal(current, 1)
  })

  it("resolveNextMilestone returns the next threshold", () => {
    assert.equal(resolveNextMilestone(18, [3, 5, 10, 20]), 20)
    assert.equal(resolveNextMilestone(25, [3, 5, 10, 20]), null)
  })
})
