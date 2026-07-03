const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  getTradingReportPeriodBounds,
  isMonthlyReportReleaseDay,
  isWeeklyReportReleaseDay,
  tradingReportPeriodId,
} = require("./tradingReportPeriods.ts")

describe("tradingReportPeriods", () => {
  it("weekly_last covers the prior calendar week", () => {
    const now = new Date("2026-07-06T12:00:00")
    const bounds = getTradingReportPeriodBounds("weekly_last", now)
    assert.equal(bounds.kind, "weekly")
    assert.equal(bounds.start.getDay(), 1)
    assert.equal(bounds.start.toISOString().slice(0, 10), "2026-06-29")
  })

  it("detects Monday as weekly release day", () => {
    assert.equal(isWeeklyReportReleaseDay(new Date("2026-07-06T09:00:00")), true)
    assert.equal(isWeeklyReportReleaseDay(new Date("2026-07-07T09:00:00")), false)
  })

  it("detects first of month as monthly release day", () => {
    assert.equal(isMonthlyReportReleaseDay(new Date("2026-07-01T09:00:00")), true)
    assert.equal(isMonthlyReportReleaseDay(new Date("2026-07-02T09:00:00")), false)
  })

  it("builds stable weekly period ids from Monday", () => {
    assert.equal(
      tradingReportPeriodId("weekly_last", new Date("2026-07-06T12:00:00")),
      "week:2026-06-29"
    )
  })
})
