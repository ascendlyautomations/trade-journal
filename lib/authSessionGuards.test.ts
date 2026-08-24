import { describe, it } from "node:test"
import {
  profileNeedsOnboarding,
  type ProfileOnboardingGateFields,
} from "./profileOnboardingGate.ts"
import assert from "node:assert/strict"

/**
 * Mirrors lib/marketingAccess.isInAppEntryFlow null-profile branch —
 * kept local so node:test does not need the @/ path alias.
 */
function missingProfileIsEntryFlow(
  loading: boolean,
  profile: ProfileOnboardingGateFields | null
) {
  if (!profile) return Boolean(loading)
  return false
}

describe("auth session guards", () => {
  it("empty profile object always looks like needs-onboarding", () => {
    // Callers must not pass profile ?? {} into profileNeedsOnboarding.
    assert.equal(profileNeedsOnboarding({}), true)
    assert.equal(
      profileNeedsOnboarding({
        onboarding_completed: true,
        username: "ok",
        trader_type: "day",
        trading_style: "scalp",
        started_trading: "2020-01-01",
      }),
      false
    )
  })

  it("missing profile after loading settles is not treated as entry-flow", () => {
    assert.equal(missingProfileIsEntryFlow(true, null), true)
    assert.equal(missingProfileIsEntryFlow(false, null), false)
  })
})
export {}
