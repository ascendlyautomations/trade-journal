import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  RR_TARGET_MIN_PAIRED_RECOMMEND,
  computeDashboardRrTargetAnalysis,
  isRrTargetingEligibleTrade,
} from "./dashboardRrTargetAnalysis.ts"

describe("isRrTargetingEligibleTrade", () => {
  it("requires both fields and positive target", () => {
    assert.equal(isRrTargetingEligibleTrade({ rr: 2, max_rr_reached: 1 }), true)
    assert.equal(isRrTargetingEligibleTrade({ rr: 2, max_rr_reached: 0 }), true)
    assert.equal(isRrTargetingEligibleTrade({ rr: 0, max_rr_reached: 1 }), false)
    assert.equal(isRrTargetingEligibleTrade({ rr: 2, max_rr_reached: null }), false)
    assert.equal(isRrTargetingEligibleTrade({ rr: null, max_rr_reached: 2 }), false)
  })
})

describe("computeDashboardRrTargetAnalysis", () => {
  it("excludes incomplete trades from all panel metrics", () => {
    const result = computeDashboardRrTargetAnalysis([
      { rr: 2, max_rr_reached: null, pnl: 100 },
      { rr: 4, max_rr_reached: null, pnl: 50 },
      { rr: 10, max_rr_reached: null, pnl: 200 },
    ])
    assert.equal(result.pairedCount, 0)
    assert.equal(result.avgTargetRr, null)
    assert.equal(result.avgMaxRrReached, null)
    assert.equal(result.avgTargetAttainmentRatio, null)
    assert.equal(result.sampleSummary, null)
  })

  it("does not let unpaired winners affect paired averages", () => {
    const result = computeDashboardRrTargetAnalysis([
      { rr: 5, max_rr_reached: 2.5, pnl: -100 },
      { rr: 5, max_rr_reached: 2.5, pnl: -50 },
      { rr: 10, max_rr_reached: null, pnl: 200 },
    ])
    assert.equal(result.pairedCount, 2)
    assert.equal(result.avgTargetRr, 5)
    assert.equal(result.avgMaxRrReached, 2.5)
    assert.equal(result.avgTargetAttainmentRatio, 0.5)
    assert.ok(result.sampleSummary?.startsWith("Based on 2 trades with both values recorded."))
  })

  it("computes target attainment above 100% when max exceeds target", () => {
    const result = computeDashboardRrTargetAnalysis([
      { rr: 2, max_rr_reached: 3, pnl: -10 },
    ])
    assert.equal(result.avgTargetAttainmentRatio, 1.5)
    assert.ok(
      result.bullets.some((b) => b.includes("150%") || b.includes("above 100%"))
    )
  })

  it("allows max R:R of zero on paired trades", () => {
    const result = computeDashboardRrTargetAnalysis([
      { rr: 3, max_rr_reached: 0, pnl: -100 },
    ])
    assert.equal(result.pairedCount, 1)
    assert.equal(result.avgMaxRrReached, 0)
    assert.equal(result.avgTargetAttainmentRatio, 0)
  })

  it("avoids strong recommendations on small paired samples", () => {
    const result = computeDashboardRrTargetAnalysis([
      { rr: 5, max_rr_reached: 1, pnl: -100 },
      { rr: 5, max_rr_reached: 1, pnl: -50 },
    ])
    assert.ok(result.pairedCount < RR_TARGET_MIN_PAIRED_RECOMMEND)
    assert.ok(result.bullets.some((b) => b.includes("Early read")))
    assert.ok(
      !result.bullets.some((b) => b.includes("profit guarantee"))
    )
  })

  it("reports excluded filtered trades in sample summary", () => {
    const result = computeDashboardRrTargetAnalysis([
      { rr: 4, max_rr_reached: 2, pnl: -10 },
      { rr: 3, max_rr_reached: null, pnl: 500 },
    ])
    assert.equal(result.pairedCount, 1)
    assert.ok(result.sampleSummary?.includes("Based on 1 trade with both values recorded."))
    assert.ok(result.sampleSummary?.includes("excluded"))
  })
})
