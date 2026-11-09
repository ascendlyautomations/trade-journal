import { describe, it } from "node:test"
import assert from "node:assert/strict"
import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { buildTradingScorecard } from "./buildScorecard.ts"
import { scoreConsistencyCategory } from "./consistency.ts"
import { scoreDisciplineCategory } from "./discipline.ts"
import { scorePsychologyCategory } from "./psychologyCategory.ts"
import { scoreRiskCategory } from "./risk.ts"
import {
  consistencyPlanAdherencePool,
  MIN_POST_LOSS_PLAN_TAGGED,
  postLossPlanObservations,
} from "./planAdherence.ts"
import {
  mapDashboardRowToScorecardTrade,
  mergeScorecardTrades,
  postTripleLossWinRate,
} from "./tradeMapping.ts"
import { resolveScorecardReliability } from "./reliability.ts"
import {
  scorecardScopeFiltersEqual,
  scorecardScopeKey,
} from "./scorecardSessionStore.ts"
import type { ScorecardTrade } from "./types.ts"
import {
  SCORECARD_CATEGORY_WEIGHTS,
  SCORECARD_MIN_TRADES_OVERALL,
  SCORECARD_MIN_TRADING_DAYS_OVERALL,
} from "./types.ts"
import type { PsychologyReportTrade } from "../psychology/reports/types.ts"

function makeTrade(index: number, overrides: Partial<ScorecardTrade> = {}): ScorecardTrade {
  const day = `2026-09-${String(2 + (index % 8)).padStart(2, "0")}`
  return {
    id: `t-${index}`,
    pnl: index % 3 === 0 ? -50 : 80,
    rr: index % 2 === 0 ? 1.5 : null,
    maxRrReached: index % 4 === 0 ? 1.2 : null,
    realizedRr: null,
    followedPlan: null,
    mistakeType: null,
    confidence: null,
    executionRating: null,
    entryTimeMs: Date.parse(`${day}T14:00:00.000Z`) + index * 3600_000,
    tradingDayKey: day,
    psychologyDayKey: day,
    ...overrides,
  }
}

/** Strict alternating loss → tagged trade in chronological order (each tag counts as post-loss). */
function tradesWithPostLossTags(count: number, followRate = 0.8): ScorecardTrade[] {
  const trades: ScorecardTrade[] = []
  let t = Date.parse("2026-09-02T10:00:00.000Z")
  const day = "2026-09-02"
  for (let i = 0; i < count; i++) {
    t += 3600_000
    trades.push({
      ...makeTrade(i * 2, { pnl: -40, followedPlan: null }),
      id: `loss-${i}`,
      entryTimeMs: t,
      tradingDayKey: day,
      psychologyDayKey: day,
    })
    t += 3600_000
    const followed =
      followRate >= 1 ? true : followRate <= 0 ? false : i % 2 === 0
    trades.push({
      ...makeTrade(i * 2 + 1, { pnl: 30, followedPlan: followed }),
      id: `after-${i}`,
      entryTimeMs: t,
      tradingDayKey: day,
      psychologyDayKey: day,
    })
  }
  return trades
}

function checkIn(date: string): TraderDailyCheckIn {
  return {
    id: `c-${date}`,
    ownerProfileId: "user",
    checkInDate: date,
    sleepHours: 7,
    sleepQuality: 4,
    morningRating: 4,
    stressLevel: 2,
    energyLevel: 4,
    focusLevel: 4,
    notes: null,
    createdAt: `${date}T12:00:00.000Z`,
    updatedAt: `${date}T12:00:00.000Z`,
  }
}

describe("planAdherence pool", () => {
  it("does not add triple-loss window trades when post-loss pool already suffices", () => {
    const trades = tradesWithPostLossTags(12, 1)
    const post = postLossPlanObservations(trades)
    const pool = consistencyPlanAdherencePool(trades)
    assert.ok(post.length >= MIN_POST_LOSS_PLAN_TAGGED)
    assert.equal(pool.observations.length, post.length)
    assert.equal(pool.tripleWindowAddedCount, 0)
  })
})

describe("scoreConsistencyCategory", () => {
  it("scores post-loss plan adherence, not win rate after 3 losses", () => {
    const trades = tradesWithPostLossTags(12, 1)
    const cat = scoreConsistencyCategory(trades, 8, 0.2)
    assert.ok(cat.score != null)
    assert.equal(cat.score, 100)
    const winCtx = cat.subMetrics.find((m) => m.id === "streak.after_three_losses_win_rate")
    assert.ok(winCtx)
    assert.ok(!cat.subMetrics.some((m) => m.label.includes("Win rate") && m.id !== "streak.after_three_losses_win_rate"))
  })

  it("stays unscored below 3 post-loss tags and scores at 3", () => {
    const short = tradesWithPostLossTags(2, 1)
    const unscored = scoreConsistencyCategory(short, 1, null)
    assert.equal(unscored.score, null)
    assert.equal(unscored.eligible, false)

    const ready = scoreConsistencyCategory(tradesWithPostLossTags(3, 1), 1, null)
    assert.equal(ready.score, 100)
    assert.equal(ready.eligible, true)
    assert.equal(ready.reliability, "earlySignal")
  })
})

describe("scoreRiskCategory", () => {
  it("never produces a numerical score in Phase 1", () => {
    const trades = Array.from({ length: 20 }, (_, i) =>
      makeTrade(i, { rr: 2, maxRrReached: 1.5, realizedRr: 1.1 })
    )
    const cat = scoreRiskCategory(trades, 500, 100, -50)
    assert.equal(cat.score, null)
    assert.equal(cat.eligible, false)
    assert.ok(cat.subMetrics.some((m) => m.id === "risk.target_attainment_context"))
    assert.ok(cat.subMetrics.some((m) => m.id === "risk.avg_loss_vs_win_context"))
  })
})

describe("scorePsychologyCategory", () => {
  it("is insights-only with no numerical score", () => {
    const trades = Array.from({ length: 10 }, (_, i) => makeTrade(i, { followedPlan: true }))
    const checkIns = ["2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05", "2026-09-06"].map(
      checkIn
    )
    const cat = scorePsychologyCategory(trades, checkIns, 6)
    assert.equal(cat.score, null)
    assert.equal(cat.eligible, false)
    assert.ok(cat.subMetrics.some((m) => m.id === "psych.phase1_mode"))
  })
})

describe("scoreDisciplineCategory", () => {
  it("requires 3 explicit plan tags", () => {
    const trades = Array.from({ length: 2 }, (_, i) => makeTrade(i, { followedPlan: true }))
    assert.equal(scoreDisciplineCategory(trades).score, null)
    const three = Array.from({ length: 3 }, (_, i) => makeTrade(i, { followedPlan: true, pnl: 40 }))
    assert.equal(scoreDisciplineCategory(three).score, 100)
    assert.equal(scoreDisciplineCategory(three).reliability, "earlySignal")
  })
})

describe("buildTradingScorecard overall", () => {
  it("returns building when trade count below overall minimum", () => {
    const trades = Array.from({ length: 2 }, (_, i) => makeTrade(i))
    const result = buildTradingScorecard({
      scopeLabel: "Test",
      trades,
      checkIns: [],
      analytics: {
        periodTradingDayCount: 6,
        maxDrawdown: 200,
        avgWin: 100,
        avgLoss: -50,
        totalTrades: trades.length,
        postTripleLossWinRate: null,
      },
    })
    assert.equal(result.overall.status, "building")
    assert.equal(result.overall.score, null)
    assert.ok(result.overall.statusMessage.includes(String(SCORECARD_MIN_TRADES_OVERALL)))
  })

  it("produces an early overall score from one category", () => {
    const trades = Array.from({ length: 3 }, (_, i) =>
      makeTrade(i, { followedPlan: true, pnl: 40 })
    )
    const result = buildTradingScorecard({
      scopeLabel: "Test",
      trades,
      checkIns: [],
      analytics: {
        periodTradingDayCount: SCORECARD_MIN_TRADING_DAYS_OVERALL,
        maxDrawdown: 0,
        avgWin: 80,
        avgLoss: -40,
        totalTrades: trades.length,
        postTripleLossWinRate: null,
      },
    })
    assert.equal(result.overall.status, "ready")
    assert.equal(result.overall.score, 100)
    assert.equal(result.overall.reliability, "earlySignal")
    assert.equal(result.overall.contributions.length, 1)
    assert.equal(result.overall.contributions[0]?.id, "discipline")
    assert.ok(Math.abs(result.overall.contributions[0]!.effectiveWeight - 1) < 0.01)
    assert.equal(result.categories.find((c) => c.id === "consistency")?.score, null)
    assert.equal(result.categories.find((c) => c.id === "risk")?.score, null)
    assert.equal(result.categories.find((c) => c.id === "psychology")?.score, null)
  })

  it("produces overall when two categories score with enough nominal weight", () => {
    const postLoss = tradesWithPostLossTags(12, 0.75)
    let t = postLoss[postLoss.length - 1].entryTimeMs + 3600_000
    const disciplineTagged = Array.from({ length: 10 }, (_, i) => {
      t += 3600_000
      return {
        ...makeTrade(100 + i, { followedPlan: i < 8, pnl: 50 }),
        id: `disc-${i}`,
        entryTimeMs: t,
      }
    })
    const trades = [...postLoss, ...disciplineTagged]
    const result = buildTradingScorecard({
      scopeLabel: "Test scope",
      trades,
      checkIns: [],
      analytics: {
        periodTradingDayCount: 8,
        maxDrawdown: 150,
        avgWin: 90,
        avgLoss: -45,
        totalTrades: trades.length,
        postTripleLossWinRate: 0.4,
      },
    })
    assert.equal(result.overall.status, "ready")
    assert.ok(result.overall.score != null)
    assert.ok(result.overall.contributions.length >= 2)
    const effectiveSum = result.overall.contributions.reduce(
      (s, c) => s + c.effectiveWeight,
      0
    )
    assert.ok(Math.abs(effectiveSum - 1) < 0.01)
    const risk = result.categories.find((c) => c.id === "risk")
    assert.equal(risk!.score, null)
    const psych = result.categories.find((c) => c.id === "psychology")
    assert.equal(psych!.score, null)
  })
})

describe("scorecard reliability bands", () => {
  it("uses 3, 8, and 20 as the band edges", () => {
    assert.equal(resolveScorecardReliability(2), "insufficient")
    assert.equal(resolveScorecardReliability(3), "earlySignal")
    assert.equal(resolveScorecardReliability(7), "earlySignal")
    assert.equal(resolveScorecardReliability(8), "developing")
    assert.equal(resolveScorecardReliability(19), "developing")
    assert.equal(resolveScorecardReliability(20), "strong")
  })
})

describe("postTripleLossWinRate", () => {
  it("stays hidden until the recovery window has 5 trades", () => {
    const short = Array.from({ length: 5 }, (_, index) =>
      makeTrade(index, { pnl: index < 3 ? -10 : 50 })
    )
    assert.equal(postTripleLossWinRate(short), null)

    const full = Array.from({ length: 8 }, (_, index) =>
      makeTrade(index, { pnl: index < 3 ? -10 : 50 })
    )
    assert.equal(postTripleLossWinRate(full), 1)
  })
})

describe("tradeMapping", () => {
  it("keeps planned and realized RR separate on merge", () => {
    const dashboard = [
      {
        id: "x",
        entry_time: "2026-09-02T14:00:00.000Z",
        pnl: 100,
        rr: 2,
        realized_rr: 1.1,
      },
    ]
    const journal: PsychologyReportTrade[] = [
      {
        id: "x",
        entryAtMs: Date.parse("2026-09-02T14:00:00.000Z"),
        entry_time: "2026-09-02T14:00:00.000Z",
        pnl: 100,
        rr: 3,
        realizedRr: 1.1,
        emotion: null,
        confidence: null,
        followedPlan: null,
        executionRating: null,
      },
    ]
    const merged = mergeScorecardTrades(dashboard, journal)
    assert.equal(merged[0].rr, 3)
    assert.equal(merged[0].realizedRr, 1.1)
  })
})

describe("scorecard scope persistence helpers", () => {
  it("detects equal scope filters", () => {
    const a = {
      accountFilter: "all",
      accountTypeFilter: "all",
      timeFilter: "30d",
      selectedDate: "2026-09-02",
      customRangeStart: "",
      customRangeEnd: "",
      showPublicOnly: false,
    }
    assert.equal(scorecardScopeFiltersEqual(a, { ...a }), true)
  })

  it("builds scope key without trade count", () => {
    const key = scorecardScopeKey({
      userId: "u1",
      accountFilter: "all",
      accountTypeFilter: "all",
      timeFilter: "30d",
      selectedDate: "",
      customRangeStart: "",
      customRangeEnd: "",
      showPublicOnly: false,
    })
    assert.ok(key.startsWith("u1|"))
  })
})

describe("category weight constants", () => {
  it("sums to 1", () => {
    const sum = Object.values(SCORECARD_CATEGORY_WEIGHTS).reduce((a, b) => a + b, 0)
    assert.ok(Math.abs(sum - 1) < 0.001)
  })
})
