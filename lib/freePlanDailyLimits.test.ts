import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  FREE_PLAN_DAILY_CLIP_LIMIT,
  FREE_PLAN_DAILY_CLIP_LIMIT_MESSAGE,
  FREE_PLAN_DAILY_POST_LIMIT,
  FREE_PLAN_DAILY_TRADE_LIMIT,
  FREE_PLAN_DAILY_TRADE_LIMIT_MESSAGE,
  parseFreePlanDailyLimitError,
} from "./freePlanDailyLimits.ts"

describe("freePlanDailyLimits", () => {
  it("exports daily limits of 3", () => {
    assert.equal(FREE_PLAN_DAILY_TRADE_LIMIT, 3)
    assert.equal(FREE_PLAN_DAILY_POST_LIMIT, 3)
    assert.equal(FREE_PLAN_DAILY_CLIP_LIMIT, 3)
  })

  it("formats canonical user-facing limit messages", () => {
    assert.equal(
      FREE_PLAN_DAILY_TRADE_LIMIT_MESSAGE,
      "You've reached the Free plan limit of 3 trades every 24 hours."
    )
    assert.equal(
      FREE_PLAN_DAILY_CLIP_LIMIT_MESSAGE,
      "You've reached the Free plan limit of 3 clips every 24 hours."
    )
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
        message: "Free plan allows only 3 posts per day",
      }),
      "post"
    )
  })

  it("detects clip limit by exception code", () => {
    assert.equal(
      parseFreePlanDailyLimitError({ message: "FREE_PLAN_DAILY_CLIP_LIMIT" }),
      "clip"
    )
  })

  it("detects trade limit from 24-hour wording", () => {
    assert.equal(
      parseFreePlanDailyLimitError({
        message: "You've reached the Free plan limit of 3 trades every 24 hours.",
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
