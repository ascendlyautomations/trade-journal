import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  MOBILE_WEB_TRADES_LOAD_FAILED,
  mobileWebNetworkErrorMessage,
  mobileWebTradesLoadErrorMessage,
} from "./mobileWebNetworkRecovery.ts"
import { USER_FACING_ERROR_MESSAGES } from "./userFacingError.ts"

describe("mobileWebNetworkRecovery", () => {
  it("maps unknown errors to safe fallback copy", () => {
    const msg = mobileWebNetworkErrorMessage(
      { message: "PGRST301" },
      MOBILE_WEB_TRADES_LOAD_FAILED
    )
    assert.equal(typeof msg, "string")
    assert.equal(msg.includes("PGRST"), false)
  })

  it("returns null for empty trades load errors", () => {
    assert.equal(mobileWebTradesLoadErrorMessage(null), null)
    assert.equal(mobileWebTradesLoadErrorMessage("  "), null)
  })

  it("does not echo raw postgres codes in trades messages", () => {
    const msg = mobileWebTradesLoadErrorMessage("Failed to fetch")
    assert.ok(msg)
    assert.notEqual(msg, "Failed to fetch")
    const network = mobileWebNetworkErrorMessage(new TypeError("Failed to fetch"))
    assert.equal(network.includes("Failed to fetch"), false)
    assert.equal(
      network === USER_FACING_ERROR_MESSAGES.CONNECTION_ERROR ||
        network === USER_FACING_ERROR_MESSAGES.NETWORK_ERROR,
      true
    )
  })
})
