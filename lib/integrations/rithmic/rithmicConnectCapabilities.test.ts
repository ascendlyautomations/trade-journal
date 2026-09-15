import assert from "node:assert/strict"
import { afterEach, describe, it } from "node:test"
import { resolveRithmicConnectCapabilities } from "@/lib/integrations/rithmic/rithmicConnectCapabilities"

describe("resolveRithmicConnectCapabilities", () => {
  const prior: Record<string, string | undefined> = {}

  afterEach(() => {
    for (const [key, value] of Object.entries(prior)) {
      if (value === undefined) delete process.env[key]
      else process.env[key] = value
    }
  })

  function setEnv(key: string, value: string | undefined) {
    if (!(key in prior)) prior[key] = process.env[key]
    if (value === undefined) delete process.env[key]
    else process.env[key] = value
  }

  it("showConnectUi when user connect enabled and test protocol env loads", () => {
    setEnv("RITHMIC_USER_CONNECT_ENABLED", "1")
    setEnv("RITHMIC_API_ENV", "test")
    setEnv("RITHMIC_WSS_URL", "wss://rituz00100.rithmic.com:443")

    const caps = resolveRithmicConnectCapabilities()
    assert.equal(caps.userConnectEnabled, true)
    assert.equal(caps.apiEnvironment, "test")
    assert.equal(caps.showConnectUi, true)
  })

  it("showConnectUi false when user connect disabled", () => {
    setEnv("RITHMIC_USER_CONNECT_ENABLED", "0")
    setEnv("RITHMIC_API_ENV", "test")

    const caps = resolveRithmicConnectCapabilities()
    assert.equal(caps.userConnectEnabled, false)
    assert.equal(caps.showConnectUi, false)
  })

  it("showConnectUi false for production without vendor confirmation", () => {
    setEnv("RITHMIC_USER_CONNECT_ENABLED", "1")
    setEnv("RITHMIC_API_ENV", "production")
    setEnv("RITHMIC_PRODUCTION_USER_AUTH_CONFIRMED", "0")

    const caps = resolveRithmicConnectCapabilities()
    assert.equal(caps.apiEnvironment, "production")
    assert.equal(caps.productionUserAuthConfirmed, false)
    assert.equal(caps.showConnectUi, false)
  })

  it("does not require protocolEnv object truthiness when env label is test", () => {
    setEnv("RITHMIC_USER_CONNECT_ENABLED", "1")
    setEnv("RITHMIC_API_ENV", undefined)
    setEnv("RITHMIC_WSS_URL", "wss://rituz00100.rithmic.com:443")

    const caps = resolveRithmicConnectCapabilities()
    assert.equal(caps.showConnectUi, true)
  })
})
