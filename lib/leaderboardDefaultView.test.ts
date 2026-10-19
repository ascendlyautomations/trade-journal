import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  countDistinctRankedTraders,
  pickDefaultLeaderboardPresetFromProbes,
} from "./leaderboardDefaultViewSelection.ts"
import type { LeaderboardRankedTrader } from "./leaderboardChart.ts"

function trader(userId: string): LeaderboardRankedTrader {
  return {
    rank: 1,
    userId,
    totalPnl: 0,
    tradeCount: 1,
    avgRR: null,
  }
}

describe("leaderboardDefaultView", () => {
  it("counts distinct ranked trader user ids", () => {
    assert.equal(
      countDistinctRankedTraders([
        trader("a"),
        trader("a"),
        trader("b"),
        trader(""),
      ]),
      2
    )
  })

  it("picks shortest preset with at least three traders", () => {
    const picked = pickDefaultLeaderboardPresetFromProbes([
      { view: "7D", count: 2 },
      { view: "30D", count: 4 },
      { view: "90D", count: 10 },
    ])
    assert.equal(picked, "30D")
  })

  it("when none reach three, picks preset with the most traders", () => {
    const picked = pickDefaultLeaderboardPresetFromProbes([
      { view: "7D", count: 1 },
      { view: "30D", count: 2 },
      { view: "90D", count: 0 },
    ])
    assert.equal(picked, "30D")
  })

  it("prefers shortest preset on tied trader counts", () => {
    const picked = pickDefaultLeaderboardPresetFromProbes([
      { view: "7D", count: 2 },
      { view: "30D", count: 2 },
      { view: "ALL", count: 2 },
    ])
    assert.equal(picked, "7D")
  })

  it("falls back to 7D when no probes succeeded", () => {
    assert.equal(pickDefaultLeaderboardPresetFromProbes([]), "7D")
  })
})
