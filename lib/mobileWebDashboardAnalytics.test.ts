import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  insightCopyAlreadyCovers,
  insightRowKind,
  insightRowTitle,
  mobileWebBarShare,
  mobileWebHourAxisLabel,
  mobileWebHourClockLabel,
  mobileWebSessionTitle,
  mobileWebSessionWinRate,
  mobileWebWeekdayCellOpacity,
  MOBILE_WEB_SESSION_ORDER,
  uniqueInsightCopy,
} from "./mobileWebDashboardAnalytics.ts"

describe("mobileWebDashboardAnalytics", () => {
  it("orders sessions New York, London, Asia and expands NY", () => {
    assert.deepEqual([...MOBILE_WEB_SESSION_ORDER], ["NY", "London", "Asia"])
    assert.equal(mobileWebSessionTitle("NY"), "New York")
    assert.equal(mobileWebSessionTitle("London"), "London")
  })

  it("computes session win rate from existing bucket stats", () => {
    assert.equal(mobileWebSessionWinRate({ totalTrades: 0, wins: 0 }), 0)
    assert.equal(mobileWebSessionWinRate({ totalTrades: 8, wins: 5 }), 62.5)
  })

  it("keeps a visible minimum bar share without changing values", () => {
    assert.equal(mobileWebBarShare(0, 100), 0)
    assert.ok(mobileWebBarShare(1, 100) >= 0.08)
    assert.equal(mobileWebBarShare(100, 100), 1)
  })

  it("maps weekday intensity to native-style opacity", () => {
    assert.equal(mobileWebWeekdayCellOpacity(0, 200), 0)
    assert.ok(mobileWebWeekdayCellOpacity(200, 200) > 0.8)
    assert.ok(mobileWebWeekdayCellOpacity(20, 200) < 0.5)
  })

  it("dedupes insight copy without dropping unique lines", () => {
    assert.deepEqual(
      uniqueInsightCopy(["  Alpha  ", "alpha", "Beta"]),
      ["  Alpha  ", "Beta"]
    )
    assert.equal(
      insightCopyAlreadyCovers(["NQ is your most profitable market"], "NQ"),
      true
    )
    assert.equal(
      insightCopyAlreadyCovers(["London session leads"], "NQ"),
      false
    )
  })

  it("formats compact hour labels", () => {
    assert.equal(mobileWebHourClockLabel(0), "12 AM")
    assert.equal(mobileWebHourClockLabel(13), "1 PM")
    assert.equal(mobileWebHourAxisLabel(0), "12a")
    assert.equal(mobileWebHourAxisLabel(18), "6p")
  })

  it("classifies insight rows for compact titles", () => {
    assert.equal(
      insightRowKind("You perform best trading London session"),
      "session"
    )
    assert.equal(
      insightRowKind("NQ is your most profitable market"),
      "symbol"
    )
    assert.equal(
      insightRowKind("You are more profitable going Long ($120)"),
      "direction"
    )
    assert.equal(insightRowTitle("combined"), "Combined setup")
  })
})
