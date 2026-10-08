import { describe, it } from "node:test"
import {
  TRADETRAXS_FEATURE_LABELS,
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_FEATURE_GROUPS,
  TRADETRAXS_PRO_PLAN,
  formatPlanFeaturesList,
  getTradeTraxsPlan,
} from "./tradeTraxsPlans.ts"
import {
  FREE_PLAN_DAILY_CLIP_PRICING_LABEL,
  FREE_PLAN_UNLIMITED_MANUAL_TRADES_LABEL,
  FREE_PLAN_UNLIMITED_POSTS_LABEL,
} from "./freePlanDailyLimits.ts"
import { FREE_PLAN_UNLIMITED_DIRECT_MESSAGES_PRICING_LABEL } from "./freePlanMessagingLimits.ts"
import { FREE_PLAN_CSV_IMPORT_PRICING_LABEL } from "./csvImportGate.ts"
import assert from "node:assert/strict"

describe("tradeTraxsPlans", () => {
  it("canonical plan names", () => {
    assert.equal(TRADETRAXS_FREE_PLAN.name, "TradeTraxs Free")
    assert.equal(TRADETRAXS_PRO_PLAN.name, "TraxPro")
  })

  it("feature lists match current gating", () => {
    assert.ok(TRADETRAXS_FREE_PLAN.features.length >= 10)
    assert.equal(TRADETRAXS_PRO_PLAN.features.length, 8)
    assert.equal(TRADETRAXS_PRO_FEATURE_GROUPS.length, 2)
    assert.ok(
      TRADETRAXS_FREE_PLAN.features.includes(FREE_PLAN_UNLIMITED_MANUAL_TRADES_LABEL)
    )
    assert.ok(TRADETRAXS_FREE_PLAN.features.includes(FREE_PLAN_UNLIMITED_POSTS_LABEL))
    assert.ok(
      TRADETRAXS_FREE_PLAN.features.includes(FREE_PLAN_DAILY_CLIP_PRICING_LABEL)
    )
    assert.ok(
      TRADETRAXS_FREE_PLAN.features.includes(
        FREE_PLAN_UNLIMITED_DIRECT_MESSAGES_PRICING_LABEL
      )
    )
    assert.equal(FREE_PLAN_CSV_IMPORT_PRICING_LABEL, "Unlimited CSV imports")
    assert.equal(FREE_PLAN_DAILY_CLIP_PRICING_LABEL, "4 Clips / day")
    assert.ok(
      TRADETRAXS_PRO_PLAN.features.includes(
        TRADETRAXS_FEATURE_LABELS.unlimitedClips
      )
    )
    assert.ok(
      TRADETRAXS_PRO_PLAN.features.includes(
        TRADETRAXS_FEATURE_LABELS.advancedPropFirmAnalytics
      )
    )
    assert.ok(
      !TRADETRAXS_PRO_PLAN.features.some((f) =>
        /Unlimited manual trades|Unlimited CSV|Unlimited Direct Messages/i.test(f)
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
