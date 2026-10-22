import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  hasActiveMembership,
  isSubscriptionExempt,
  needsSubscriptionCheckout,
  resolvePostAuthAppPath,
} from "./subscriptionAccess.ts"

const completeFreeProfile = {
  onboarding_completed: true,
  username: "trader1",
  trader_type: "day",
  trading_style: "scalp",
  started_trading: "2020-01-01",
  use_free_tier: false,
  is_pro: false,
  creator_access: false,
  subscription_status: null,
  trial_end: null,
  is_beta_tester: false,
}

describe("isSubscriptionExempt", () => {
  it("treats onboarding-complete free users as exempt without use_free_tier", () => {
    assert.equal(isSubscriptionExempt(completeFreeProfile), true)
  })

  it("still exempts explicit use_free_tier and Pro", () => {
    assert.equal(
      isSubscriptionExempt({ ...completeFreeProfile, use_free_tier: true }),
      true
    )
    assert.equal(
      isSubscriptionExempt({
        ...completeFreeProfile,
        is_pro: false,
        subscription_status: "active",
      }),
      true
    )
  })
})

describe("needsSubscriptionCheckout", () => {
  it("is false for existing onboarded free accounts", () => {
    assert.equal(needsSubscriptionCheckout(completeFreeProfile), false)
  })

  it("is false while onboarding is still required", () => {
    assert.equal(
      needsSubscriptionCheckout({
        onboarding_completed: false,
        username: null,
        trader_type: null,
        trading_style: null,
        started_trading: null,
        use_free_tier: false,
      }),
      false
    )
  })
})

describe("hasActiveMembership", () => {
  it("includes onboarded free users", () => {
    assert.equal(hasActiveMembership(completeFreeProfile), true)
  })
})

describe("resolvePostAuthAppPath", () => {
  it("sends onboarded users to dashboard", () => {
    assert.equal(resolvePostAuthAppPath(completeFreeProfile), "/dashboard")
  })

  it("sends incomplete profiles to onboarding", () => {
    assert.equal(
      resolvePostAuthAppPath({
        onboarding_completed: false,
        username: null,
      }),
      "/onboarding"
    )
  })
})
