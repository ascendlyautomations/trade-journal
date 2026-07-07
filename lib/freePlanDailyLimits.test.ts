import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  FREE_PLAN_DAILY_POST_LIMIT,
  FREE_PLAN_DAILY_TRADE_LIMIT,
  parseFreePlanDailyLimitError,
} from "./freePlanDailyLimits"

describe("freePlanDailyLimits", () => {
  it("exports daily limits of 3", () => {
    assert.equal(FREE_PLAN_DAILY_TRADE_LIMIT, 3)
    assert.equal(FREE_PLAN_DAILY_POST_LIMIT, 3)
  })

  it("detects trade limit by exception code", () => {
    assert.equal(
      parseFreePlanDailyLimitError({ message: "FREE_PLAN_DAILY_TRADE_LIMIT" }),
      "trade"
    )
  })

  it("detects post limit from postgres message", () => {
    assert.equal(
      parseFreePlanDailyLimitError({
        code: "P0001",
        message: "Free plan allows only 1 post per day",
      }),
      "post"
    )
  })

  it("detects trade limit from 24-hour wording", () => {
    assert.equal(
      parseFreePlanDailyLimitError({
        message: "Free plan allows only 3 trades per 24 hours",
      }),
      "trade"
    )
  })

  it("returns null for unrelated errors", () => {
    assert.equal(
      parseFreePlanDailyLimitError({ message: "network timeout" }),
      null
    )
  })
})
