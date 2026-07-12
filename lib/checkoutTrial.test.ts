import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  CHECKOUT_TRIAL_ENABLED,
  profileHasUsedCheckoutTrial,
  resolveCheckoutTrialPeriodDays,
} from "./checkoutTrial.ts"

describe("checkoutTrial", () => {
  it("trial is enabled for production checkout", () => {
    assert.equal(CHECKOUT_TRIAL_ENABLED, true)
  })

  it("eligible new users receive a trial period", () => {
    const days = resolveCheckoutTrialPeriodDays({ trial_end: null })
    assert.ok(days != null && days > 0)
  })

  it("users with a prior trial_end do not receive another trial", () => {
    assert.equal(profileHasUsedCheckoutTrial({ trial_end: "2026-01-01T00:00:00.000Z" }), true)
    assert.equal(
      resolveCheckoutTrialPeriodDays({ trial_end: "2026-01-01T00:00:00.000Z" }),
      null
    )
  })

  it("empty trial_end strings are treated as unused", () => {
    assert.equal(profileHasUsedCheckoutTrial({ trial_end: "  " }), false)
    assert.ok(resolveCheckoutTrialPeriodDays({ trial_end: "" }) != null)
  })
})
