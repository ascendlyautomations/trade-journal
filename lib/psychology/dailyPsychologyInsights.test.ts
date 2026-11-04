import { describe, it } from "node:test"
import assert from "node:assert/strict"
import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { buildMatchedTradingDays } from "./matchedTradingDays.ts"
import {
  buildEarlyPsychologyInsightCards,
  resolveMatchedDayReliability,
} from "./dailyPsychologyInsights.ts"
import { psychologyTradeDateKey } from "./tradeDateKey.ts"

function checkIn(date: string, overrides: Partial<TraderDailyCheckIn> = {}): TraderDailyCheckIn {
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
    ...overrides,
  }
}

function trade(id: string, entryTime: string, pnl: number) {
  return { id, entry_time: entryTime, created_at: entryTime, pnl }
}

describe("buildMatchedTradingDays", () => {
  it("sums P&L once per trading day when multiple trades share a check-in date", () => {
    const entry = "2026-09-02T14:00:00.000Z"
    const key = psychologyTradeDateKey(trade("a", entry, 100))
    const days = buildMatchedTradingDays(
      [
        trade("a", entry, 100),
        trade("b", "2026-09-02T15:00:00.000Z", -40),
      ],
      [checkIn(key)]
    )
    assert.equal(days.length, 1)
    assert.equal(days[0]?.dailyPnL, 60)
    assert.equal(days[0]?.tradeCount, 2)
    assert.equal(days[0]?.winCount, 1)
    assert.equal(days[0]?.lossCount, 1)
  })

  it("ignores check-ins with no trades in the filtered set", () => {
    const days = buildMatchedTradingDays(
      [trade("a", "2026-09-02T14:00:00.000Z", 10)],
      [checkIn("2026-09-02"), checkIn("2026-09-09")]
    )
    assert.equal(days.length, 1)
    assert.equal(days[0]?.dateKey, "2026-09-02")
  })
})

describe("buildEarlyPsychologyInsightCards", () => {
  it("returns overview and dimension cards with a single matched day", () => {
    const key = "2026-09-02"
    const cards = buildEarlyPsychologyInsightCards(
      [trade("a", "2026-09-02T14:00:00.000Z", 85)],
      [checkIn(key, { sleepQuality: 5, focusLevel: 5 })]
    )
    assert.ok(cards.length >= 1)
    assert.equal(cards.some((c) => c.id === "matchedDays.overview"), true)
    assert.ok(cards.every((c) => c.reliability !== "insufficient"))
  })

  it("builds a comparison when good and poor sleep days exist", () => {
    const cards = buildEarlyPsychologyInsightCards(
      [
        trade("a", "2026-09-02T14:00:00.000Z", 200),
        trade("b", "2026-09-03T14:00:00.000Z", -50),
      ],
      [
        checkIn("2026-09-02", { sleepQuality: 5 }),
        checkIn("2026-09-03", { sleepQuality: 1 }),
      ]
    )
    assert.equal(cards.some((c) => c.id === "sleepQuality.compare"), true)
  })

  it("shows single-group sleep performance when only good sleep days exist", () => {
    const cards = buildEarlyPsychologyInsightCards(
      [trade("a", "2026-09-02T14:00:00.000Z", 120)],
      [checkIn("2026-09-02", { sleepQuality: 5 })]
    )
    assert.equal(cards.some((c) => c.id === "sleepQuality.good"), true)
  })
})

describe("resolveMatchedDayReliability", () => {
  it("marks one matched day as early signal", () => {
    assert.equal(resolveMatchedDayReliability(1, 3), "earlySignal")
  })
})
