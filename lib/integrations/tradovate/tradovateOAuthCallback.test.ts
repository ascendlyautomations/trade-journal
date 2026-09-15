import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  parseTradovateCallbackQuery,
  TRADOVATE_OAUTH_REDIRECT_URI,
  TRADOVATE_NATIVE_OAUTH_RETURN_URL,
  buildNativeTradovateIntegrationResultUrl,
  buildTradovateIntegrationResultUrl,
  isAllowedNativeTradovateOAuthReturn,
  tradovateCallbackUserMessage,
} from "./tradovateOAuthCallback"

describe("tradovateOAuthCallback", () => {
  it("uses canonical www redirect URI", () => {
    assert.equal(
      TRADOVATE_OAUTH_REDIRECT_URI,
      "https://www.tradetraxs.com/api/integrations/tradovate/callback"
    )
  })

  it("parses OAuth query params", () => {
    const params = new URLSearchParams(
      "code=abc&state=xyz&error=access_denied&error_description=nope"
    )
    const parsed = parseTradovateCallbackQuery(params)
    assert.equal(parsed.code, "abc")
    assert.equal(parsed.state, "xyz")
    assert.equal(parsed.oauthError, "access_denied")
    assert.equal(parsed.oauthErrorDescription, "nope")
  })

  it("maps token exchange errors to user copy", () => {
    const msg = tradovateCallbackUserMessage({ kind: "error", reason: "token_exchange" })
    assert.match(msg, /could not finish linking/i)
  })

  it("builds settings redirect URLs", () => {
    const req = new Request("https://www.tradetraxs.com/api/integrations/tradovate/callback")
    const url = buildTradovateIntegrationResultUrl(req, {
      kind: "error",
      reason: "invalid_state",
    })
    assert.match(url, /\/settings\/integrations\/tradovate\?/)
    assert.match(url, /reason=invalid_state/)
  })

  it("allows native iOS Tradovate OAuth return URL", () => {
    assert.equal(
      TRADOVATE_NATIVE_OAUTH_RETURN_URL,
      "tradetraxs://settings/broker-integrations/tradovate"
    )
    assert.equal(isAllowedNativeTradovateOAuthReturn(TRADOVATE_NATIVE_OAUTH_RETURN_URL), true)
    assert.equal(isAllowedNativeTradovateOAuthReturn("https://evil.example/steal"), false)
  })

  it("builds native broker integration redirect URLs", () => {
    const url = buildNativeTradovateIntegrationResultUrl({ kind: "success" })
    assert.match(url, /^tradetraxs:\/\/settings\/broker-integrations\/tradovate\?/)
    assert.match(url, /status=success/)
  })
})
