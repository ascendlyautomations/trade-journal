import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  TRADOVATE_NATIVE_OAUTH_CLIENT,
  TRADOVATE_NATIVE_OAUTH_CLIENT_HEADER,
  TRADOVATE_NATIVE_OAUTH_REDIRECT_AFTER,
  buildNativeTradovateAuthorizeJsonResponse,
  buildWebTradovateAuthorizeJsonResponse,
  isNativeTradovateAuthorizeRequest,
  isValidHttpsAuthorizeUrl,
  parseTradovateAuthorizePostBody,
} from "./tradovateAuthorizePost"

describe("tradovateAuthorizePost", () => {
  it("parses native client in JSON body", () => {
    const body = parseTradovateAuthorizePostBody({ client: "native" })
    assert.equal(isNativeTradovateAuthorizeRequest(body, null), true)
  })

  it("parses native client case-insensitively", () => {
    const body = parseTradovateAuthorizePostBody({ client: " Native " })
    assert.equal(isNativeTradovateAuthorizeRequest(body, null), true)
  })

  it("detects native via broker OAuth client header", () => {
    const body = parseTradovateAuthorizePostBody({})
    assert.equal(
      isNativeTradovateAuthorizeRequest(body, "native"),
      true
    )
    assert.equal(TRADOVATE_NATIVE_OAUTH_CLIENT_HEADER, "x-tradetraxs-broker-oauth-client")
  })

  it("web POST body without client is not native", () => {
    const body = parseTradovateAuthorizePostBody({
      reconnectConnectionId: "conn-1",
    })
    assert.equal(isNativeTradovateAuthorizeRequest(body, null), false)
  })

  it("native JSON response includes authorizeUrl", () => {
    const json = buildNativeTradovateAuthorizeJsonResponse(
      "https://trader.tradovate.com/oauth?response_type=code&client_id=x&redirect_uri=y&state=z"
    )
    assert.equal(json.ok, true)
    assert.match(json.authorizeUrl, /^https:\/\//)
    assert.equal(isValidHttpsAuthorizeUrl(json.authorizeUrl), true)
  })

  it("web JSON response is ok-only handoff contract", () => {
    assert.deepEqual(buildWebTradovateAuthorizeJsonResponse(), { ok: true })
  })

  it("native redirect_after matches iOS deep link contract", () => {
    assert.equal(
      TRADOVATE_NATIVE_OAUTH_REDIRECT_AFTER,
      "tradetraxs://settings/broker-integrations/tradovate"
    )
  })

  it("rejects empty native authorize URL", () => {
    assert.throws(
      () => buildNativeTradovateAuthorizeJsonResponse("  "),
      /tradovate_native_authorize_url_missing/
    )
  })

  it("does not treat arbitrary client values as native", () => {
    assert.equal(TRADOVATE_NATIVE_OAUTH_CLIENT, "native")
    const body = parseTradovateAuthorizePostBody({ client: "ios" })
    assert.equal(isNativeTradovateAuthorizeRequest(body, null), false)
  })
})
