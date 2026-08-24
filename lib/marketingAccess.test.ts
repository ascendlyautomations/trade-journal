import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { shouldShowMarketingNavbar } from "./marketingAccess.ts"

describe("shouldShowMarketingNavbar", () => {
  it("always shows on homepage for logged-out users, even while auth loading", () => {
    assert.equal(shouldShowMarketingNavbar("/", null, null, true), true)
    assert.equal(shouldShowMarketingNavbar("/", null, null, false), true)
    assert.equal(shouldShowMarketingNavbar("/", undefined, null, true), true)
  })

  it("keeps chrome visible during authenticated loading so logout never blanks the header", () => {
    assert.equal(
      shouldShowMarketingNavbar("/", { id: "user-1" }, null, true),
      true
    )
  })

  it("hides for authenticated users known to still need entry flow", () => {
    assert.equal(
      shouldShowMarketingNavbar(
        "/",
        { id: "user-1" },
        {
          onboarding_completed: false,
          username: null,
          trader_type: null,
          trading_style: null,
          started_trading: null,
        },
        false
      ),
      false
    )
  })

  it("shows for completed members on the homepage", () => {
    assert.equal(
      shouldShowMarketingNavbar(
        "/",
        { id: "user-1" },
        {
          onboarding_completed: true,
          username: "nick",
          trader_type: "day",
          trading_style: "scalp",
          started_trading: "2020-01-01",
          is_pro: true,
          subscription_status: "active",
          creator_access: false,
          trial_end: null,
          use_free_tier: false,
          is_beta_tester: false,
        },
        false
      ),
      true
    )
  })
})
