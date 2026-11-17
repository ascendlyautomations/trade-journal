import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { generateTradingReportForWeek } from "@/lib/tradingReports/generateTradingReport"
import { tradingReportNotificationHref } from "@/lib/notificationsDisplay"
import {
  getTradingReportPeriodBounds,
  saturdayCurrentWeekReport,
} from "@/lib/tradingReports/tradingReportPeriods"
import {
  readTradingReportPushStatus,
  tradingReportPushNeedsRetry,
  writeTradingReportPushStatus,
} from "@/lib/tradingReports/tradingReportPushDelivery"
import { isWeeklyTradingReportPushWindow } from "@/lib/server/tradingReports/weeklyTradingReportPushWindow"

describe("Saturday weekly report eligibility", () => {
  it("uses the current Eastern week on Saturday, Monday through Saturday", () => {
    const winterSaturday = new Date("2026-11-14T17:00:00Z")
    const winter = saturdayCurrentWeekReport(winterSaturday)
    assert.equal(isWeeklyTradingReportPushWindow(winterSaturday), true)
    assert.equal(winter.periodId, "week:2026-11-09")
    assert.equal(winter.startKey, "2026-11-09")
    assert.equal(winter.endKey, "2026-11-14")
    assert.equal(winter.href, "/dashboard?report=week%3A2026-11-09")
    const previousWeek = getTradingReportPeriodBounds("weekly_last", winterSaturday)
    assert.equal(previousWeek.startKey, "2026-11-02")
    assert.notEqual(winter.startKey, previousWeek.startKey)

    const summerRetry = new Date("2026-07-11T18:00:00Z")
    const summer = saturdayCurrentWeekReport(summerRetry)
    assert.equal(isWeeklyTradingReportPushWindow(summerRetry), true)
    assert.equal(summer.periodId, "week:2026-07-06")
    assert.equal(summer.endKey, "2026-07-11")
  })

  it("keeps the 17:00 and 18:00 UTC runs inside the Eastern window and rejects the edges", () => {
    assert.equal(isWeeklyTradingReportPushWindow(new Date("2026-11-14T17:00:00Z")), true)
    assert.equal(isWeeklyTradingReportPushWindow(new Date("2026-11-14T18:00:00Z")), true)
    assert.equal(isWeeklyTradingReportPushWindow(new Date("2026-07-11T17:00:00Z")), true)
    assert.equal(isWeeklyTradingReportPushWindow(new Date("2026-07-11T18:00:00Z")), true)
    assert.equal(isWeeklyTradingReportPushWindow(new Date("2026-11-14T16:59:00Z")), false)
    assert.equal(isWeeklyTradingReportPushWindow(new Date("2026-07-11T19:00:00Z")), false)
    assert.equal(isWeeklyTradingReportPushWindow(new Date("2026-11-13T17:00:00Z")), false)
  })
})

describe("weekly report push retry", () => {
  it("retries until a push is sent, without treating the row as delivered", () => {
    const content = JSON.stringify({
      periodId: "week:2026-11-09",
      href: "/dashboard?report=week%3A2026-11-09",
    })
    assert.equal(readTradingReportPushStatus(content), "pending")
    assert.equal(tradingReportPushNeedsRetry("pending"), true)
    assert.equal(tradingReportPushNeedsRetry("failed"), true)
    assert.equal(tradingReportPushNeedsRetry("no_tokens"), true)
    assert.equal(tradingReportPushNeedsRetry("sent"), false)
    assert.equal(tradingReportPushNeedsRetry("skipped"), false)

    const sent = writeTradingReportPushStatus(content, "sent", new Date("2026-11-14T17:05:00Z"))
    assert.equal(readTradingReportPushStatus(sent), "sent")
    assert.match(sent, /week:2026-11-09/)
    assert.equal(tradingReportPushNeedsRetry(readTradingReportPushStatus(sent)), false)
  })
})

describe("historical weekly report navigation", () => {
  it("keeps trades from the stored Monday and drops the following week", () => {
    const report = generateTradingReportForWeek(
      [
        { id: "in-week", entry_time: "2026-11-10T15:00:00Z", pnl: 25, mode: "funded" },
        { id: "next-week", entry_time: "2026-11-16T15:00:00Z", pnl: 40, mode: "funded" },
      ],
      "2026-11-09",
      new Date("2026-11-21T17:00:00Z")
    )
    assert.ok(report)
    assert.equal(report.metrics.tradesTaken, 1)
    assert.equal(report.bestTradeId, "in-week")
    assert.match(report.dateRangeLabel, /Nov/)

    const href = tradingReportNotificationHref({
      id: "n1",
      user_id: "u1",
      sender_id: null,
      type: "trading_report",
      post_id: null,
      trade_id: null,
      profile_post_id: null,
      achievement_post_id: null,
      reel_id: null,
      comment_id: null,
      room_id: null,
      content: JSON.stringify({
        href: "/dashboard?report=weekly_last",
        periodId: "week:2026-11-09",
        periodKey: "weekly_last",
      }),
      created_at: "2026-11-14T17:00:00Z",
      read: false,
    })
    assert.equal(href, "/dashboard?report=week%3A2026-11-09")
    assert.equal(
      generateTradingReportForWeek([], "2026-11-10", new Date("2026-11-21T17:00:00Z")),
      null
    )
  })
})
