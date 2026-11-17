import { describe, it } from "node:test"
import { absoluteTradingWeekBounds, getTradingReportPeriodBounds, isMonthlyReportReleaseDay, isWeeklyReportReleaseDay, parseTradingReportWeekPeriodId, tradingReportPeriodId, } from "./tradingReportPeriods.ts"
import assert from "node:assert/strict"

describe("tradingReportPeriods", () => {
  it("weekly_last covers the prior calendar week", () => {
    const now = new Date("2026-07-06T16:00:00Z")
    const bounds = getTradingReportPeriodBounds("weekly_last", now)
    assert.equal(bounds.kind, "weekly")
    assert.equal(bounds.startKey, "2026-06-29")
    assert.equal(bounds.endKey, "2026-07-05")
    assert.equal(bounds.partial, false)
  })

  it("detects Monday as weekly release day", () => {
    assert.equal(isWeeklyReportReleaseDay(new Date("2026-07-06T16:00:00Z")), true)
    assert.equal(isWeeklyReportReleaseDay(new Date("2026-07-07T16:00:00Z")), false)
  })

  it("detects first of month as monthly release day", () => {
    assert.equal(isMonthlyReportReleaseDay(new Date("2026-07-01T16:00:00Z")), true)
    assert.equal(isMonthlyReportReleaseDay(new Date("2026-07-02T16:00:00Z")), false)
  })

  it("builds stable weekly period ids from Monday", () => {
    assert.equal(
      tradingReportPeriodId("weekly_last", new Date("2026-07-06T16:00:00Z")),
      "week:2026-06-29"
    )
  })

  it("opens a stored week after that week is no longer last week", () => {
    const later = new Date("2026-11-21T17:00:00Z")
    const bounds = absoluteTradingWeekBounds("2026-11-09", later)
    assert.equal(bounds.startKey, "2026-11-09")
    assert.equal(bounds.endKey, "2026-11-15")
    assert.equal(bounds.partial, false)
    assert.equal(parseTradingReportWeekPeriodId("week:2026-11-10"), null)
    assert.equal(parseTradingReportWeekPeriodId("weekly_last"), null)
  })
})
export {}
