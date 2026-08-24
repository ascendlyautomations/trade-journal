import { describe, it } from "node:test"
import { profileNeedsOnboarding, profileNeedsUsername, isAllowedPathDuringOnboarding, } from "./profileOnboardingGate.ts"
import assert from "node:assert/strict"

describe("profileNeedsUsername", () => {
  it("treats null, empty, and whitespace as missing", () => {
    assert.equal(profileNeedsUsername(null), true)
    assert.equal(profileNeedsUsername(""), true)
    assert.equal(profileNeedsUsername("   "), true)
    assert.equal(profileNeedsUsername("trader1"), false)
  })
})

describe("profileNeedsOnboarding", () => {
  const completeProfile = {
    username: "trader1",
    trader_type: "Day Trader",
    trading_style: "Scalping",
    started_trading: "2020-01-01",
    onboarding_completed: true,
  }

  it("never gates users with onboarding_completed true (existing users)", () => {
    assert.equal(
      profileNeedsOnboarding({
        ...completeProfile,
        onboarding_completed: true,
        trader_type: null,
        trading_style: null,
      }),
      false
    )
  })

  it("requires username and core fields for new users", () => {
    assert.equal(
      profileNeedsOnboarding({
        username: null,
        onboarding_completed: false,
      }),
      true
    )

    assert.equal(
      profileNeedsOnboarding({
        username: "trader1",
        trader_type: "Day Trader",
        trading_style: "Scalping",
        started_trading: "2020-01-01",
        onboarding_completed: false,
      }),
      true
    )

    assert.equal(profileNeedsOnboarding(completeProfile), false)
  })
})

describe("isAllowedPathDuringOnboarding", () => {
  it("allows auth, onboarding, and legal routes only", () => {
    assert.equal(isAllowedPathDuringOnboarding("/onboarding"), true)
    assert.equal(isAllowedPathDuringOnboarding("/choose-plan"), true)
    assert.equal(isAllowedPathDuringOnboarding("/early-access/welcome"), true)
    assert.equal(isAllowedPathDuringOnboarding("/login"), true)
    assert.equal(isAllowedPathDuringOnboarding("/reset-password"), true)
    assert.equal(isAllowedPathDuringOnboarding("/privacy"), true)
    assert.equal(isAllowedPathDuringOnboarding("/terms"), true)
    assert.equal(isAllowedPathDuringOnboarding("/refund-policy"), true)
    assert.equal(isAllowedPathDuringOnboarding("/creator"), true)
    assert.equal(isAllowedPathDuringOnboarding("/"), false)
    assert.equal(isAllowedPathDuringOnboarding("/faq"), false)
    assert.equal(isAllowedPathDuringOnboarding("/pricing"), false)
    assert.equal(isAllowedPathDuringOnboarding("/demo"), false)
    assert.equal(isAllowedPathDuringOnboarding("/dashboard"), false)
    assert.equal(isAllowedPathDuringOnboarding("/feed"), false)
  })
})
export {}
