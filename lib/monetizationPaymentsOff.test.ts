import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  canPresentProPaywall,
  shouldEnforceFreeLimits,
  shouldGateProFeature,
} from "./proMonetizationPolicy.ts"
import { MONETIZATION_FLAGS_FAIL_CLOSED } from "./monetizationConfig.ts"

/** Production-default flags — regression guard for Mode A. */
const PRODUCTION_PAUSED = {
  ...MONETIZATION_FLAGS_FAIL_CLOSED,
  entitlementEnforcementEnabled: false,
  iosPaywallEnabled: false,
  webPaywallEnabled: false,
}

describe("monetization payments OFF (Mode A guard)", () => {
  it("fail-closed defaults keep all gates inactive", () => {
    assert.equal(PRODUCTION_PAUSED.entitlementEnforcementEnabled, false)
    assert.equal(PRODUCTION_PAUSED.webPaywallEnabled, false)
    assert.equal(PRODUCTION_PAUSED.iosPaywallEnabled, false)
    assert.equal(shouldEnforceFreeLimits(PRODUCTION_PAUSED), false)
    assert.equal(shouldGateProFeature(false, PRODUCTION_PAUSED), false)
    assert.equal(canPresentProPaywall("web", PRODUCTION_PAUSED), false)
    assert.equal(canPresentProPaywall("ios", PRODUCTION_PAUSED), false)
  })

  it("paywall flags alone do not gate without enforcement", () => {
    const paywallsOnEnforcementOff = {
      entitlementEnforcementEnabled: false,
      webPaywallEnabled: true,
      iosPaywallEnabled: true,
    }
    assert.equal(shouldGateProFeature(false, paywallsOnEnforcementOff), false)
    assert.equal(canPresentProPaywall("web", paywallsOnEnforcementOff), false)
  })
})
