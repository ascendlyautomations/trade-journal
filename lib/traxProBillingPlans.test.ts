const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  getTraxProBillingPlan,
  getTraxProPlanBilledAmount,
  getTraxProPlanEffectiveMonthlyAmount,
  formatTraxProEffectiveMonthly,
  getTraxProSubscriptionDisplay,
} = require("./traxProBillingPlans.ts")

describe("traxProBillingPlans", () => {
  it("monthly anchor pricing", () => {
    const plan = getTraxProBillingPlan("monthly")
    assert.equal(getTraxProPlanEffectiveMonthlyAmount(plan), 23.99)
    assert.equal(getTraxProPlanBilledAmount(plan), 23.99)
  })

  it("six month pricing — 5% off", () => {
    const plan = getTraxProBillingPlan("six_month")
    assert.equal(getTraxProPlanEffectiveMonthlyAmount(plan), 22.79)
    assert.equal(getTraxProPlanBilledAmount(plan), 136.74)
    assert.equal(formatTraxProEffectiveMonthly(plan), "$22.79/mo")
  })

  it("yearly pricing — 15% off", () => {
    const plan = getTraxProBillingPlan("yearly")
    assert.equal(getTraxProPlanEffectiveMonthlyAmount(plan), 20.39)
    assert.equal(getTraxProPlanBilledAmount(plan), 244.7)
    assert.equal(formatTraxProEffectiveMonthly(plan), "$20.39/mo")
  })

  it("subscription display labels", () => {
    assert.deepEqual(getTraxProSubscriptionDisplay("monthly"), {
      productName: "TradeTraxs Pro",
      planLabel: "Monthly Plan",
      billedLabel: "Monthly",
    })
    assert.deepEqual(getTraxProSubscriptionDisplay("six_month"), {
      productName: "TradeTraxs Pro",
      planLabel: "6-Month Plan",
      billedLabel: "Every 6 Months",
    })
    assert.deepEqual(getTraxProSubscriptionDisplay("yearly"), {
      productName: "TradeTraxs Pro",
      planLabel: "Yearly Plan",
      billedLabel: "Annually",
    })
  })
})
