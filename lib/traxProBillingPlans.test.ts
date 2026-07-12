const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  getTraxProBillingPlan,
  getTraxProPlanBilledAmount,
  getTraxProPlanEffectiveMonthlyAmount,
  formatTraxProEffectiveMonthly,
  getTraxProSubscriptionDisplay,
  getVisibleTraxProBillingPlans,
  TRAXPRO_BILLING_PLANS,
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

  it("production plan list stays three intervals", () => {
    assert.equal(TRAXPRO_BILLING_PLANS.length, 3)
    assert.deepEqual(
      TRAXPRO_BILLING_PLANS.map((plan) => plan.id),
      ["monthly", "six_month", "yearly"]
    )
  })

  it("test plan display uses $1 and is labeled Test Plan", () => {
    const plan = getTraxProBillingPlan("test")
    assert.equal(plan.label, "Test Plan")
    assert.equal(plan.checkoutOptionLabel, "Test Plan")
    assert.equal(getTraxProPlanEffectiveMonthlyAmount(plan), 1)
    assert.equal(getTraxProPlanBilledAmount(plan), 1)
    assert.deepEqual(getTraxProSubscriptionDisplay("test"), {
      productName: "TradeTraxs Pro",
      planLabel: "Test Plan",
      billedLabel: "Monthly (Test)",
    })
  })

  it("visible plans exclude test when STRIPE_PRICE_ID_TEST is unset", () => {
    const previous = process.env.STRIPE_PRICE_ID_TEST
    const previousPublic = process.env.NEXT_PUBLIC_STRIPE_TEST_PLAN_ENABLED
    delete process.env.STRIPE_PRICE_ID_TEST
    delete process.env.NEXT_PUBLIC_STRIPE_TEST_PLAN_ENABLED
    try {
      assert.equal(getVisibleTraxProBillingPlans().length, 3)
      assert.ok(!getVisibleTraxProBillingPlans().some((plan) => plan.id === "test"))
    } finally {
      if (previous === undefined) delete process.env.STRIPE_PRICE_ID_TEST
      else process.env.STRIPE_PRICE_ID_TEST = previous
      if (previousPublic === undefined) {
        delete process.env.NEXT_PUBLIC_STRIPE_TEST_PLAN_ENABLED
      } else {
        process.env.NEXT_PUBLIC_STRIPE_TEST_PLAN_ENABLED = previousPublic
      }
    }
  })

  it("visible plans include test when STRIPE_PRICE_ID_TEST is set", () => {
    const previous = process.env.STRIPE_PRICE_ID_TEST
    const previousPublic = process.env.NEXT_PUBLIC_STRIPE_TEST_PLAN_ENABLED
    process.env.STRIPE_PRICE_ID_TEST = "price_test_live_1"
    delete process.env.NEXT_PUBLIC_STRIPE_TEST_PLAN_ENABLED
    try {
      const visible = getVisibleTraxProBillingPlans()
      assert.equal(visible.length, 4)
      assert.equal(visible[3].id, "test")
    } finally {
      if (previous === undefined) delete process.env.STRIPE_PRICE_ID_TEST
      else process.env.STRIPE_PRICE_ID_TEST = previous
      if (previousPublic === undefined) {
        delete process.env.NEXT_PUBLIC_STRIPE_TEST_PLAN_ENABLED
      } else {
        process.env.NEXT_PUBLIC_STRIPE_TEST_PLAN_ENABLED = previousPublic
      }
    }
  })
})
