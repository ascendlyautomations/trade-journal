const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const { shouldShowGettingStartedIntroPopup } = require("./gettingStartedChecklist.ts")

describe("shouldShowGettingStartedIntroPopup", () => {
  it("shows on first baseline when onboarding is already complete", () => {
    assert.equal(
      shouldShowGettingStartedIntroPopup({
        onboardingCompleted: true,
        hasSeenGettingStartedIntro: false,
        prevOnboardingCompleted: false,
        isBaselineFetch: true,
      }),
      true
    )
  })

  it("shows when onboarding transitions incomplete → complete after baseline", () => {
    assert.equal(
      shouldShowGettingStartedIntroPopup({
        onboardingCompleted: true,
        hasSeenGettingStartedIntro: false,
        prevOnboardingCompleted: false,
        isBaselineFetch: false,
      }),
      true
    )
  })

  it("does not show when intro already seen", () => {
    assert.equal(
      shouldShowGettingStartedIntroPopup({
        onboardingCompleted: true,
        hasSeenGettingStartedIntro: true,
        prevOnboardingCompleted: false,
        isBaselineFetch: true,
      }),
      false
    )
  })

  it("does not show on repeat refresh after baseline with no onboarding change", () => {
    assert.equal(
      shouldShowGettingStartedIntroPopup({
        onboardingCompleted: true,
        hasSeenGettingStartedIntro: false,
        prevOnboardingCompleted: true,
        isBaselineFetch: false,
      }),
      false
    )
  })

  it("does not show while onboarding is still incomplete", () => {
    assert.equal(
      shouldShowGettingStartedIntroPopup({
        onboardingCompleted: false,
        hasSeenGettingStartedIntro: false,
        prevOnboardingCompleted: false,
        isBaselineFetch: true,
      }),
      false
    )
  })
})
