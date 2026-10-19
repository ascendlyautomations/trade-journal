import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { pickExploreWeeklyTopPerformers } from "./exploreWeeklyTopPerformersPick.ts"
import type { TradeForLeaderboard } from "./leaderboardChart.ts"

function isoDaysAgo(days: number): string {
  const d = new Date()
  d.setDate(d.getDate() - days)
  return d.toISOString()
}

describe("exploreWeeklyTopPerformers", () => {
  it("picks pnl, rr, and win rate leaders in the 7D window", () => {
    const trades: TradeForLeaderboard[] = [
      { user_id: "a", pnl: 500, rr: 1.2, created_at: isoDaysAgo(1) },
      { user_id: "a", pnl: -100, rr: 0.8, created_at: isoDaysAgo(2) },
      { user_id: "b", pnl: 200, rr: 3.5, created_at: isoDaysAgo(1) },
      { user_id: "b", pnl: -50, rr: 1, created_at: isoDaysAgo(2) },
      { user_id: "c", pnl: 50, rr: 1, created_at: isoDaysAgo(1) },
      { user_id: "c", pnl: 60, rr: 1, created_at: isoDaysAgo(2) },
      { user_id: "c", pnl: 70, rr: 1, created_at: isoDaysAgo(3) },
    ]

    const picks = pickExploreWeeklyTopPerformers(trades)
    const byCategory = Object.fromEntries(picks.map((p) => [p.category, p.userId]))

    assert.equal(byCategory.pnl, "a")
    assert.equal(byCategory.rr, "b")
    assert.equal(byCategory.winRate, "c")
  })
})
