import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  FREE_PLAN_DAILY_DM_LIMIT,
  FREE_PLAN_DAILY_DM_LIMIT_MESSAGE,
  FREE_PLAN_DAILY_DM_LIMIT_TITLE,
  isFreePlanDailyDmLimitError,
} from "./freePlanMessagingLimits.ts"

describe("freePlanMessagingLimits", () => {
  it("exports a daily DM limit of 25", () => {
    assert.equal(FREE_PLAN_DAILY_DM_LIMIT, 25)
  })

  it("formats canonical DM limit popup copy", () => {
    assert.equal(FREE_PLAN_DAILY_DM_LIMIT_TITLE, "Direct Message Limit Reached")
    assert.match(
      FREE_PLAN_DAILY_DM_LIMIT_MESSAGE,
      /maximum daily messaging limit of 25\/day on the Free plan/
    )
    assert.match(
      FREE_PLAN_DAILY_DM_LIMIT_MESSAGE,
      /25 direct messages every 24 hours/
    )
  })

  it("detects DM limit errors by exception code", () => {
    assert.equal(
      isFreePlanDailyDmLimitError({ message: "FREE_PLAN_DAILY_DM_LIMIT" }),
      true
    )
  })
})
