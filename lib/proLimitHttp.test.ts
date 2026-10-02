import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  buildProLimitPayload,
  isProLimitResponseBody,
} from "./proGateReason.ts"
import { PRO_LIMIT_REACHED_CODE } from "./proGateReason.ts"

describe("proLimitHttp", () => {
  it("builds structured PRO_LIMIT_REACHED bodies", () => {
    const body = buildProLimitPayload("daily_trades")
    assert.equal(body.code, PRO_LIMIT_REACHED_CODE)
    assert.equal(body.limit, "daily_trades")
    assert.ok(body.message.includes("3 Free trades"))
  })

  it("detects pro limit response bodies", () => {
    assert.equal(
      isProLimitResponseBody(buildProLimitPayload("account_count")),
      true
    )
    assert.equal(isProLimitResponseBody({ code: "OTHER" }), false)
  })
})
