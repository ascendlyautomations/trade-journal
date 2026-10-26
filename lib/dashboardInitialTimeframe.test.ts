import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  DASHBOARD_DEFAULT_TIME_FILTER,
  countDashboardTradesInTimeframe,
  resolveInitialDashboardTimeframe,
} from "./dashboardInitialTimeframe.ts"

const now = new Date("2026-10-26T15:00:00.000Z")

function trade(daysAgo: number, accountId = "acc-1") {
  const d = new Date(now)
  d.setDate(d.getDate() - daysAgo)
  return {
    account_id: accountId,
    mode: "live",
    entry_time: d.toISOString(),
    created_at: d.toISOString(),
  }
}

describe("resolveInitialDashboardTimeframe", () => {
  it("defaults to 30d when recent trades exist", () => {
    const resolved = resolveInitialDashboardTimeframe({
      trades: [trade(5)],
      accountFilter: "all",
      accountTypeFilter: "all",
      now,
    })
    assert.equal(resolved, "30d")
  })

  it("expands 30d → 90d → 1y → all when windows are empty", () => {
    assert.equal(
      resolveInitialDashboardTimeframe({
        trades: [trade(45)],
        accountFilter: "all",
        accountTypeFilter: "all",
        now,
      }),
      "90d"
    )
    assert.equal(
      resolveInitialDashboardTimeframe({
        trades: [trade(120)],
        accountFilter: "all",
        accountTypeFilter: "all",
        now,
      }),
      "1y"
    )
    assert.equal(
      resolveInitialDashboardTimeframe({
        trades: [trade(400)],
        accountFilter: "all",
        accountTypeFilter: "all",
        now,
      }),
      "all"
    )
  })

  it("respects account filters when counting", () => {
    const trades = [
      { ...trade(5), mode: "live" },
      { ...trade(5), mode: "funded" },
    ]
    assert.equal(
      countDashboardTradesInTimeframe({
        trades,
        timeFilter: "30d",
        accountFilter: "all",
        accountTypeFilter: "funded",
        now,
      }),
      1
    )
    assert.equal(
      resolveInitialDashboardTimeframe({
        trades,
        accountFilter: "all",
        accountTypeFilter: "funded",
        now,
      }),
      "30d"
    )
  })

  it("returns default 30d when no trades match scope", () => {
    assert.equal(
      resolveInitialDashboardTimeframe({
        trades: [],
        accountFilter: "all",
        accountTypeFilter: "all",
        now,
      }),
      DASHBOARD_DEFAULT_TIME_FILTER
    )
  })
})
