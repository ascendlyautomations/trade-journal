import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  analyzeTradeFailureFromError,
  openAiErrorMetaForLog,
} from "./openAiRouteSupport.ts"

describe("openAiRouteSupport", () => {
  it("maps OpenAI credit_balance_exhausted to openai_quota_exhausted", () => {
    const error = {
      status: 429,
      code: "credit_balance_exhausted",
      type: "insufficient_quota",
      error: {
        type: "insufficient_quota",
        code: "credit_balance_exhausted",
        message:
          "You have no credits remaining. Add credits to continue using the API.",
      },
    }
    const failure = analyzeTradeFailureFromError(error)
    assert.equal(failure.code, "openai_quota_exhausted")
    assert.match(failure.reply, /temporarily unavailable/i)
    assert.doesNotMatch(failure.reply, /busy right now/i)
  })

  it("maps true rate limits to openai_rate_limited", () => {
    const error = {
      status: 429,
      type: "rate_limit_exceeded",
      code: "rate_limit_exceeded",
    }
    const failure = analyzeTradeFailureFromError(error)
    assert.equal(failure.code, "openai_rate_limited")
  })

  it("logs only safe OpenAI metadata", () => {
    const meta = openAiErrorMetaForLog({
      status: 429,
      requestID: "req_test",
      code: "credit_balance_exhausted",
      type: "insufficient_quota",
      error: { message: "secret upstream copy should not be logged wholesale" },
    })
    assert.equal(meta.requestId, "req_test")
    assert.equal(meta.code, "credit_balance_exhausted")
    assert.equal(meta.type, "insufficient_quota")
  })
})