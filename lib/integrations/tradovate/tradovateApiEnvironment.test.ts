import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  assertTradovateRestHostMatchesEnvironment,
  parseTradovateApiEnvironmentInput,
} from "./tradovateApiEnvironment.ts"

const DEMO_REST = "https://demo.tradovateapi.com"
const LIVE_REST = "https://live.tradovateapi.com"

describe("tradovate API environment", () => {
  it("parseTradovateApiEnvironmentInput accepts demo and live only", () => {
    assert.equal(parseTradovateApiEnvironmentInput("demo"), "demo")
    assert.equal(parseTradovateApiEnvironmentInput("LIVE"), "live")
    assert.equal(parseTradovateApiEnvironmentInput("production"), null)
  })

  it("assertTradovateRestHostMatchesEnvironment rejects cross-environment base URL", () => {
    assert.doesNotThrow(() =>
      assertTradovateRestHostMatchesEnvironment({
        apiEnvironment: "demo",
        restBaseUrl: DEMO_REST,
      })
    )
    assert.throws(() =>
      assertTradovateRestHostMatchesEnvironment({
        apiEnvironment: "demo",
        restBaseUrl: LIVE_REST,
      })
    )
  })

  it("documented demo vs live REST hosts", () => {
    assert.equal(DEMO_REST, "https://demo.tradovateapi.com")
    assert.equal(LIVE_REST, "https://live.tradovateapi.com")
  })
})
