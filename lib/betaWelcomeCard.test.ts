const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  BETA_WELCOME_SEEN_STORAGE_KEY,
  shouldShowBetaWelcomeCard,
} = require("./betaWelcomeCard.ts")

describe("shouldShowBetaWelcomeCard", () => {
  const base = {
    isBetaTester: true,
    onboardingCompleted: true,
    tradeCount: 0,
    welcomeSeen: false,
  }

  it("shows for beta testers with completed onboarding and no trades", () => {
    assert.equal(shouldShowBetaWelcomeCard(base), true)
  })

  it("hides when not a beta tester", () => {
    assert.equal(shouldShowBetaWelcomeCard({ ...base, isBetaTester: false }), false)
  })

  it("hides when onboarding is incomplete", () => {
    assert.equal(
      shouldShowBetaWelcomeCard({ ...base, onboardingCompleted: false }),
      false
    )
  })

  it("hides when user has trades", () => {
    assert.equal(shouldShowBetaWelcomeCard({ ...base, tradeCount: 1 }), false)
  })

  it("hides after welcome was seen", () => {
    assert.equal(shouldShowBetaWelcomeCard({ ...base, welcomeSeen: true }), false)
  })
})

describe("BETA_WELCOME_SEEN_STORAGE_KEY", () => {
  it("uses the expected storage key prefix", () => {
    assert.equal(BETA_WELCOME_SEEN_STORAGE_KEY, "tradetraxs_beta_welcome_seen_v1")
  })
})
