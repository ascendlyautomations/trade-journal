import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  buildMobileWebCalendarYearOverview,
  compactCalendarYearPnl,
} from "./mobileWebCalendarYear.ts"

describe("compactCalendarYearPnl", () => {
  it("formats compact signed P&L", () => {
    assert.equal(compactCalendarYearPnl(0), "$0")
    assert.equal(compactCalendarYearPnl(450), "+$450")
    assert.equal(compactCalendarYearPnl(-680), "-$680")
    assert.equal(compactCalendarYearPnl(1540), "+$1.5k")
    assert.equal(compactCalendarYearPnl(12500), "+$13k")
  })
})

describe("buildMobileWebCalendarYearOverview", () => {
  it("groups Eastern trading days into months without extra fetches", () => {
    const overview = buildMobileWebCalendarYearOverview(
      [
        { pnl: 1000, entry_time: "2026-01-15T15:00:00-05:00" },
        { pnl: -200, entry_time: "2026-01-16T10:00:00-05:00" },
        { pnl: 500, entry_time: "2026-03-02T11:00:00-04:00" },
        { pnl: 50, entry_time: "2025-12-01T10:00:00-05:00" },
      ],
      2026,
      new Date("2026-10-30T16:00:00-04:00")
    )

    assert.equal(overview.year, 2026)
    assert.equal(overview.tradeCount, 3)
    assert.equal(overview.netPnl, 1300)
    assert.equal(overview.months[0].tradeCount, 2)
    assert.equal(overview.months[0].netPnl, 800)
    assert.equal(overview.months[2].netPnl, 500)
    assert.equal(overview.bestMonth, 1)
    assert.equal(overview.winRate != null && overview.winRate > 60, true)
    assert.equal(overview.months[10].isFuture, true)
    assert.equal(overview.months[9].isFuture, false)
  })
})
