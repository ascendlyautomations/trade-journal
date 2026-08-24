import { describe, it } from "node:test"
import { TRADETRAXS_FEATURE_LABELS, TRADETRAXS_FREE_PLAN, TRADETRAXS_PRO_FEATURE_GROUPS, TRADETRAXS_PRO_PLAN, formatPlanFeaturesList, getTradeTraxsPlan, } from "./tradeTraxsPlans.ts"
import { FREE_PLAN_DAILY_CLIP_PRICING_LABEL, FREE_PLAN_DAILY_POST_PRICING_LABEL, FREE_PLAN_DAILY_TRADE_PRICING_LABEL, } from "./freePlanDailyLimits.ts"
import { FREE_PLAN_DAILY_DM_PRICING_LABEL, FREE_PLAN_UNLIMITED_TRADE_ROOM_MESSAGES_PRICING_LABEL, } from "./freePlanMessagingLimits.ts"
import assert from "node:assert/strict"

describe("tradeTraxsPlans", () => {
  it("canonical plan names", () => {
    assert.equal(TRADETRAXS_FREE_PLAN.name, "TradeTraxs Free")
    assert.equal(TRADETRAXS_PRO_PLAN.name, "TradeTraxs Pro")
  })

  it("feature lists match current gating with simplified analytics copy", () => {
    assert.equal(TRADETRAXS_FREE_PLAN.features.length, 12)
    assert.equal(TRADETRAXS_PRO_PLAN.features.length, 12)
    assert.equal(TRADETRAXS_PRO_FEATURE_GROUPS.length, 5)
    assert.equal(TRADETRAXS_PRO_PLAN.featuresHeading, "Everything in Free, plus:")
    assert.ok(
      TRADETRAXS_FREE_PLAN.features.includes(FREE_PLAN_DAILY_TRADE_PRICING_LABEL)
    )
    assert.ok(
      TRADETRAXS_FREE_PLAN.features.includes(FREE_PLAN_DAILY_POST_PRICING_LABEL)
    )
    assert.ok(
      TRADETRAXS_FREE_PLAN.features.includes(FREE_PLAN_DAILY_CLIP_PRICING_LABEL)
    )
    assert.ok(
      TRADETRAXS_FREE_PLAN.features.includes(
        FREE_PLAN_UNLIMITED_TRADE_ROOM_MESSAGES_PRICING_LABEL
      )
    )
    assert.ok(
      TRADETRAXS_FREE_PLAN.features.includes(FREE_PLAN_DAILY_DM_PRICING_LABEL)
    )
    assert.ok(
      TRADETRAXS_PRO_PLAN.features.includes(
        TRADETRAXS_FEATURE_LABELS.unlimitedDirectMessages
      )
    )
    assert.ok(
      TRADETRAXS_FREE_PLAN.features.includes(
        TRADETRAXS_FEATURE_LABELS.basicAnalytics
      )
    )
    assert.ok(
      !TRADETRAXS_FREE_PLAN.features.some((feature) =>
        /Net P\/L|Profit Factor|Expectancy/i.test(feature)
      )
    )
    assert.ok(
      TRADETRAXS_PRO_PLAN.features.includes(
        TRADETRAXS_FEATURE_LABELS.premiumAnalytics
      )
    )
    assert.ok(
      !TRADETRAXS_PRO_PLAN.features.some((feature) =>
        /Profit Factor|Expectancy|Avg RR/i.test(feature)
      )
    )
    assert.ok(
      TRADETRAXS_PRO_PLAN.features.includes(
        TRADETRAXS_FEATURE_LABELS.weeklyMonthlyReports
      )
    )
    assert.ok(
      !TRADETRAXS_FREE_PLAN.features.some((feature) =>
        /AI Analyst|Backtest Lab|CSV Import/i.test(feature)
      )
    )
  })

  it("getTradeTraxsPlan returns shared objects", () => {
    assert.equal(getTradeTraxsPlan("free"), TRADETRAXS_FREE_PLAN)
    assert.equal(getTradeTraxsPlan("pro"), TRADETRAXS_PRO_PLAN)
  })

  it("formatPlanFeaturesList joins features", () => {
    assert.equal(
      formatPlanFeaturesList(TRADETRAXS_FREE_PLAN, "; "),
      TRADETRAXS_FREE_PLAN.features.join("; ")
    )
  })
})
export {}
