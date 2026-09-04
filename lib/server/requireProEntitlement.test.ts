import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { isProActive } from "../subscription.ts"

describe("requireProEntitlement policy (isProActive)", () => {
  it("rejects a typical free profile before AI would run", () => {
    assert.equal(
      isProActive({
        is_pro: false,
        creator_access: false,
        subscription_status: null,
        trial_end: null,
      }),
      false
    )
  })

  it("accepts manual TraxPro via is_pro", () => {
    assert.equal(
      isProActive({
        is_pro: true,
        subscription_status: null,
      }),
      true
    )
  })

  it("accepts active Stripe subscription", () => {
    assert.equal(
      isProActive({
        is_pro: false,
        subscription_status: "active",
      }),
      true
    )
  })
})
