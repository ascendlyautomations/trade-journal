import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  describePasswordGrantFailure,
  formatSetupAuthFailure,
  maskPerfEmail,
  redactSensitiveAuthText,
} from "../../loadtest/lib/auth-grant-diagnostics.js"

describe("auth grant diagnostics", () => {
  it("masks perf emails", () => {
    assert.equal(maskPerfEmail("tradetraxsdemo+perfload26@gmail.com"), "tr***@gmail.com")
  })

  it("parses GoTrue rate limit JSON", () => {
    const f = describePasswordGrantFailure(
      429,
      JSON.stringify({
        code: 429,
        error_code: "over_request_rate_limit",
        msg: "Request rate limit reached",
      })
    )
    assert.equal(f.httpStatus, 429)
    assert.equal(f.reason, "over_request_rate_limit")
    assert.match(f.detail, /rate limit/i)
  })

  it("redacts tokens from error text", () => {
    const t = redactSensitiveAuthText('password":"secret" access_token":"abc.def.ghi"')
    assert.doesNotMatch(t, /secret/)
    assert.doesNotMatch(t, /abc\.def/)
  })

  it("formats setup failure without password", () => {
    const msg = formatSetupAuthFailure(25, "tradetraxsdemo+perfload26@gmail.com", {
      httpStatus: 429,
      reason: "over_request_rate_limit",
      detail: "Request rate limit reached",
    })
    assert.match(msg, /index 25/)
    assert.match(msg, /perfload26|tr\*\*\*@gmail\.com/)
    assert.match(msg, /HTTP 429/)
    assert.doesNotMatch(msg, /password/i)
  })
})
