import { toUserFacingErrorMessage } from "./userFacingError.ts"
import type { SignupIntent } from "./signupFlow.ts"

export type WebSocialOAuthProvider = "google" | "apple"

export type WebSocialOAuthSignupContext = {
  isLogin: boolean
  agreedToTerms: boolean
  earlyAccessPromotionEnabled: boolean
  signupPlanIntent: SignupIntent | null
  /** When true, signup flow requires an explicit plan choice (non–early-access). */
  requireSignupPlanIntent: boolean
}

export type WebSocialOAuthRedirectContext = WebSocialOAuthSignupContext & {
  safeNextPath: string | null
  shouldStartCheckout: boolean
  /** Override post-signup destination (creator redeem, etc.). */
  signupRedirectPath?: string
}

/**
 * Validates signup prerequisites before OAuth (terms, plan intent).
 * Returns a user-facing error message, or null when OK.
 */
export function validateWebSocialOAuthSignup(
  ctx: WebSocialOAuthSignupContext
): string | null {
  if (ctx.isLogin) return null

  if (!ctx.agreedToTerms) {
    return "You must agree to the Terms of Service and Privacy Policy before creating an account."
  }

  if (ctx.earlyAccessPromotionEnabled) return null

  if (ctx.requireSignupPlanIntent && !ctx.signupPlanIntent) {
    return "Choose Start Free Trial or Continue Free below before signing up."
  }

  return null
}

/** Resolves the in-app path Supabase should redirect to after OAuth. */
export function resolveWebSocialOAuthRedirectPath(
  ctx: WebSocialOAuthRedirectContext
): string {
  if (ctx.signupRedirectPath) return ctx.signupRedirectPath

  if (!ctx.isLogin) {
    return ctx.earlyAccessPromotionEnabled
      ? "/early-access/welcome"
      : "/onboarding"
  }

  if (ctx.shouldStartCheckout) {
    return "/login?next=checkout"
  }

  return ctx.safeNextPath ?? "/dashboard"
}

export function mapWebSocialOAuthError(error: unknown): string {
  const message =
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof (error as { message?: unknown }).message === "string"
      ? (error as { message: string }).message
      : String(error ?? "")

  const lower = message.toLowerCase()

  if (
    lower.includes("popup closed") ||
    lower.includes("user cancelled") ||
    lower.includes("user canceled") ||
    lower.includes("access_denied") ||
    lower.includes("authorization cancelled")
  ) {
    return "Sign in was cancelled."
  }

  if (
    lower.includes("provider is not enabled") ||
    lower.includes("not enabled") ||
    lower.includes("unsupported provider") ||
    lower.includes("invalid_client") ||
    lower.includes("invalid request") ||
    lower.includes("redirect_uri_mismatch")
  ) {
    return "Apple sign-in is not configured yet. Please try another sign-in method."
  }

  if (lower.includes("email address is already registered")) {
    return "An account with this email already exists. Try signing in with email or Google."
  }

  if (lower.includes("identity already exists")) {
    return "This Apple ID is already linked to another sign-in method. Try signing in with email or Google."
  }

  return toUserFacingErrorMessage(error)
}

/** True when relay addresses from Hide My Email should be treated as valid. */
export function isApplePrivateRelayEmail(email: string | null | undefined): boolean {
  if (!email) return false
  return /@privaterelay\.appleid\.com$/i.test(email.trim())
}
