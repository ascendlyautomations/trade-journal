import { describe, it } from "node:test"
import assert from "node:assert/strict"
import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { buildTradingScorecard } from "./buildScorecard.ts"
import { scoreDisciplineCategory } from "./discipline.ts"
import { scorePsychologyCategory } from "./psychologyCategory.ts"
import { scoreRiskCategory } from "./risk.ts"
import {
  mapDashboardRowToScorecardTrade,
  mergeScorecardTrades,
} from "./tradeMapping.ts"
import {
  scorecardScopeFiltersEqual,
  scorecardScopeKey,
} from "./scorecardSessionStore.ts"
import type { ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS, SCORECARD_MIN_TRADES_OVERALL } from "./types.ts"
import type { PsychologyReportTrade } from "../psychology/reports/types.ts"

function makeTrade(index: number, overrides: Partial<ScorecardTrade> = {}): ScorecardTrade {
  const day = `2026-09-${String(2 + (index % 5)).padStart(2, "0")}`
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

describe("scoreRiskCategory", () => {
  it("uses absolute average loss magnitude when avgLoss is negative", () => {
    const trades = Array.from({ length: 12 }, (_, i) =>
      makeTrade(i, { rr: 1.5, maxRrReached: 1.0 })
    )
    const cat = scoreRiskCategory(trades, 200, 100, -45)
    const lossMetric = cat.subMetrics.find((m) => m.id === "risk.avg_loss_vs_win")
    assert.ok(lossMetric, "expected avg loss vs win sub-metric")
    assert.ok(cat.score != null)
    assert.equal(lossMetric!.value, "0.45×")
  })

  it("does not score documentation-only when no outcome proxies exist", () => {
    const trades = Array.from({ length: 8 }, (_, i) =>
      makeTrade(i, { pnl: 10, rr: null, maxRrReached: null })
    )
    const cat = scoreRiskCategory(trades, 0, 10, 0)
    assert.equal(cat.score, null)
    assert.equal(cat.eligible, false)
  })
})

describe("tradeMapping", () => {
  it("treats omitted followed_plan as unknown on dashboard rows", () => {
    const row = mapDashboardRowToScorecardTrade({
      id: "a",
      entry_time: "2026-09-02T14:00:00.000Z",
      pnl: 50,
      followed_plan: null,
    })
    assert.equal(row!.followedPlan, null)
  })

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

describe("scoreDisciplineCategory", () => {
  it("does not treat null followedPlan as negative", () => {
    const trades = Array.from({ length: 10 }, (_, i) =>
      makeTrade(i, { followedPlan: null })
    )
    const cat = scoreDisciplineCategory(trades)
    assert.equal(cat.score, null)
    assert.ok(cat.dataGaps.some((g) => g.includes("Tag plan")))
  })

  it("scores explicit plan adherence only among tagged trades", () => {
    const trades = [
      ...Array.from({ length: 5 }, (_, i) => makeTrade(i, { followedPlan: true })),
      ...Array.from({ length: 5 }, (_, i) => makeTrade(i + 5, { followedPlan: null })),
    ]
    const cat = scoreDisciplineCategory(trades)
    const adherence = cat.subMetrics.find((m) => m.id === "discipline.plan_adherence")
    assert.ok(adherence)
    assert.equal(adherence!.value, "100%")
    assert.equal(cat.score, 100)
  })
})

describe("psychologyCategory cross-day boundaries", () => {
  it("matches check-ins on Eastern calendar day, not futures session key alone", () => {
    const entry = "2026-09-02T22:30:00.000-04:00"
    const trades: ScorecardTrade[] = [
      {
        id: "t1",
        pnl: 50,
        rr: null,
        maxRrReached: null,
        realizedRr: null,
        followedPlan: true,
        mistakeType: null,
        confidence: null,
        executionRating: null,
        entryTimeMs: Date.parse(entry),
        tradingDayKey: "2026-09-03",
        psychologyDayKey: "2026-09-02",
      },
    ]
    const checkIns = [checkIn("2026-09-02")]
    const cat = scorePsychologyCategory(trades, checkIns, 1)
    const matched = cat.subMetrics.find((m) => m.id === "psych.matched_days")
    assert.equal(matched!.value, "1")
  })
})

describe("buildTradingScorecard overall", () => {
  it("returns building status when trade count below overall minimum", () => {
    const trades = Array.from({ length: 10 }, (_, i) => makeTrade(i))
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

  it("renormalizes category weights when only some categories score", () => {
    const trades = Array.from({ length: 24 }, (_, i) =>
      makeTrade(i, {
        followedPlan: i % 2 === 0,
        rr: 1.2,
        maxRrReached: 1.0,
      })
    )
    const result = buildTradingScorecard({
      scopeLabel: "Test",
      trades,
      checkIns: [],
      analytics: {
        periodTradingDayCount: 8,
        maxDrawdown: 150,
        avgWin: 90,
        avgLoss: -45,
        totalTrades: trades.length,
        postTripleLossWinRate: 0.6,
      },
    })
    assert.equal(result.overall.status, "ready")
    assert.ok(result.overall.contributions.length >= 2)
    const effectiveSum = result.overall.contributions.reduce(
      (s, c) => s + c.effectiveWeight,
      0
    )
    assert.ok(Math.abs(effectiveSum - 1) < 0.01)
    const nominalSum = result.overall.contributions.reduce(
      (s, c) => s + c.nominalWeight,
      0
    )
    assert.ok(nominalSum < 1)
    assert.ok(result.overall.nominalWeightIncluded < 1)
  })

  it("produces overall score when gates and discipline sample met", () => {
    const trades = Array.from({ length: 24 }, (_, i) =>
      makeTrade(i, {
        followedPlan: true,
        rr: 1.2,
        maxRrReached: 1.0,
      })
    )
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
        postTripleLossWinRate: 0.5,
      },
    })
    assert.equal(result.overall.status, "ready")
    assert.ok(result.overall.score != null)
    const discipline = result.categories.find((c) => c.id === "discipline")
    assert.ok(discipline!.score != null)
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
    const b = { ...a }
    assert.equal(scorecardScopeFiltersEqual(a, b), true)
    assert.equal(
      scorecardScopeFiltersEqual(a, { ...b, selectedDate: "2026-09-03" }),
      false
    )
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
    assert.ok(!key.includes("|24"))
    assert.ok(key.startsWith("u1|"))
  })
})

describe("category weight constants", () => {
  it("sums to 1", () => {
    const sum = Object.values(SCORECARD_CATEGORY_WEIGHTS).reduce((a, b) => a + b, 0)
    assert.ok(Math.abs(sum - 1) < 0.001)
  })
})
