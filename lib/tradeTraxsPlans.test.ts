const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
  formatPlanFeaturesList,
  getTradeTraxsPlan,
} = require("./tradeTraxsPlans.ts")

describe("tradeTraxsPlans", () => {
  it("canonical plan names", () => {
    assert.equal(TRADETRAXS_FREE_PLAN.name, "TradeTraxs Free")
    assert.equal(TRADETRAXS_PRO_PLAN.name, "TradeTraxs Pro")
  })

  it("feature lists are concise", () => {
    assert.equal(TRADETRAXS_FREE_PLAN.features.length, 6)
    assert.equal(TRADETRAXS_PRO_PLAN.features.length, 10)
    assert.equal(TRADETRAXS_PRO_PLAN.featuresHeading, "Everything in Free, plus:")
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
