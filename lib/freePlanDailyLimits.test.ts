import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  FREE_PLAN_DAILY_CLIP_LIMIT,
  FREE_PLAN_DAILY_CLIP_LIMIT_MESSAGE,
  parseFreePlanDailyLimitError,
} from "./freePlanDailyLimits.ts"

describe("freePlanDailyLimits", () => {
  it("clip cap is 4 per UTC day", () => {
    assert.equal(FREE_PLAN_DAILY_CLIP_LIMIT, 4)
    assert.match(FREE_PLAN_DAILY_CLIP_LIMIT_MESSAGE, /4 Clips/)
    assert.match(FREE_PLAN_DAILY_CLIP_LIMIT_MESSAGE, /UTC calendar day/)
  })

  it("parseFreePlanDailyLimitError detects clip limits only", () => {
    assert.equal(
      parseFreePlanDailyLimitError({ message: "FREE_PLAN_DAILY_CLIP_LIMIT" }),
      "clip"
    )
    assert.equal(
      parseFreePlanDailyLimitError({ message: "FREE_PLAN_DAILY_TRADE_LIMIT" }),
      null
    )
  })
})
export {}
