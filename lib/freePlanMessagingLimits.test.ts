import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  FREE_PLAN_UNLIMITED_DIRECT_MESSAGES_PRICING_LABEL,
  isFreePlanDailyDmLimitError,
} from "./freePlanMessagingLimits.ts"

describe("freePlanMessagingLimits", () => {
  it("free plan includes unlimited DMs", () => {
    assert.equal(
      FREE_PLAN_UNLIMITED_DIRECT_MESSAGES_PRICING_LABEL,
      "Unlimited direct messages"
    )
  })

  it("no subscription DM cap errors", () => {
    assert.equal(isFreePlanDailyDmLimitError({ message: "FREE_PLAN_DAILY_DM_LIMIT" }), false)
  })
})
export {}
