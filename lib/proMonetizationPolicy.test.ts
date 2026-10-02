import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  canPresentProPaywall,
  entitlementGatingActive,
  shouldGateProFeature,
} from "./proMonetizationPolicy.ts"

describe("proMonetizationPolicy", () => {
  it("stays off when enforcement is false", () => {
    const flags = {
      iosPaywallEnabled: true,
      webPaywallEnabled: true,
      entitlementEnforcementEnabled: false,
    }
    assert.equal(entitlementGatingActive(flags), false)
    assert.equal(canPresentProPaywall("web", flags), false)
    assert.equal(shouldGateProFeature(false, flags), false)
  })

  it("requires paywall for upgrade presentation", () => {
    const flags = {
      iosPaywallEnabled: false,
      webPaywallEnabled: true,
      entitlementEnforcementEnabled: true,
    }
    assert.equal(canPresentProPaywall("web", flags), true)
    assert.equal(canPresentProPaywall("ios", flags), false)
  })
})
