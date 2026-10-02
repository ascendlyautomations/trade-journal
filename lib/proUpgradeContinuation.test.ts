import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  isSafeAutomaticRetry,
  safeRetryForProGateReason,
} from "./proUpgradeContinuation.ts"

describe("proUpgradeContinuation", () => {
  it("maps Pro features to safe routes only", () => {
    const action = safeRetryForProGateReason({
      type: "feature",
      feature: "ai_analyst",
    })
    assert.equal(action.kind, "open_route")
    if (action.kind === "open_route") {
      assert.equal(action.path, "/analyst")
    }
    assert.equal(isSafeAutomaticRetry(action), true)
  })

  it("does not auto-retry limits", () => {
    const action = safeRetryForProGateReason({
      type: "limit",
      limit: "daily_trades",
    })
    assert.equal(action.kind, "none")
    assert.equal(isSafeAutomaticRetry(action), false)
  })
})
