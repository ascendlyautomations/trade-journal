import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  isApplePrivateRelayEmail,
  mapWebSocialOAuthError,
  resolveWebSocialOAuthRedirectPath,
  validateWebSocialOAuthSignup,
} from "./webSocialOAuthPolicy.ts"

describe("validateWebSocialOAuthSignup", () => {
  it("allows login without terms", () => {
    assert.equal(
      validateWebSocialOAuthSignup({
        isLogin: true,
        agreedToTerms: false,
        earlyAccessPromotionEnabled: false,
        signupPlanIntent: null,
        requireSignupPlanIntent: true,
      }),
      null
    )
  })

  it("requires terms on signup", () => {
    const msg = validateWebSocialOAuthSignup({
      isLogin: false,
      agreedToTerms: false,
      earlyAccessPromotionEnabled: false,
      signupPlanIntent: "free",
      requireSignupPlanIntent: true,
    })
    assert.match(msg ?? "", /Terms of Service/)
  })
})

describe("resolveWebSocialOAuthRedirectPath", () => {
  const base = {
    isLogin: false,
    agreedToTerms: true,
    earlyAccessPromotionEnabled: false,
    signupPlanIntent: "free" as const,
    requireSignupPlanIntent: true,
    safeNextPath: null,
    shouldStartCheckout: false,
  }

  it("sends new signups to onboarding", () => {
    assert.equal(resolveWebSocialOAuthRedirectPath(base), "/onboarding")
  })

  it("sends returning login to dashboard", () => {
    assert.equal(
      resolveWebSocialOAuthRedirectPath({ ...base, isLogin: true }),
      "/dashboard"
    )
  })

  it("honors safe next path on login", () => {
    assert.equal(
      resolveWebSocialOAuthRedirectPath({
        ...base,
        isLogin: true,
        safeNextPath: "/settings",
      }),
      "/settings"
    )
  })

  it("routes checkout continuation through login", () => {
    assert.equal(
      resolveWebSocialOAuthRedirectPath({
        ...base,
        isLogin: true,
        shouldStartCheckout: true,
      }),
      "/login?next=checkout"
    )
  })
})

describe("mapWebSocialOAuthError", () => {
  it("maps user cancellation", () => {
    assert.equal(
      mapWebSocialOAuthError({ message: "User cancelled the login" }),
      "Sign in was cancelled."
    )
  })

  it("maps provider misconfiguration", () => {
    assert.match(
      mapWebSocialOAuthError({ message: "Provider apple is not enabled" }),
      /not configured/i
    )
  })
})

describe("isApplePrivateRelayEmail", () => {
  it("accepts Hide My Email relay addresses", () => {
    assert.equal(
      isApplePrivateRelayEmail("abc123@privaterelay.appleid.com"),
      true
    )
  })

  it("rejects normal emails", () => {
    assert.equal(isApplePrivateRelayEmail("user@example.com"), false)
  })
})
