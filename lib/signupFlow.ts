import type { TraxProBillingIntervalId } from "./traxProBillingPlans"
import {
  isTraxProBillingIntervalId,
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
} from "./traxProBillingPlans"
import { isCreatorFlowActive } from "./creatorAccess"

const SIGNUP_FLOW_KEY = "tt_signup_flow"
const SIGNUP_INTENT_KEY = "tt_signup_intent"
const CHECKOUT_BILLING_INTERVAL_KEY = "tt_checkout_billing_interval"

export type SignupIntent = "trial" | "free"

/** User clicked Start Free Trial — they have left the marketing site. */
export function enterSignupFlow(): void {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(SIGNUP_FLOW_KEY, "1")
  } catch {
    /* ignore */
  }
}

export function clearSignupFlow(): void {
  if (typeof window === "undefined") return
  try {
    sessionStorage.removeItem(SIGNUP_FLOW_KEY)
  } catch {
    /* ignore */
  }
}

export function isSignupFlowActive(): boolean {
  if (typeof window === "undefined") return false
  try {
    return sessionStorage.getItem(SIGNUP_FLOW_KEY) === "1"
  } catch {
    return false
  }
}

export function setSignupIntent(intent: SignupIntent): void {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(SIGNUP_INTENT_KEY, intent)
    if (intent === "trial") {
      enterSignupFlow()
    }
  } catch {
    /* ignore */
  }
}

export function getSignupIntent(): SignupIntent | null {
  if (typeof window === "undefined") return null
  try {
    const raw = sessionStorage.getItem(SIGNUP_INTENT_KEY)
    return raw === "trial" || raw === "free" ? raw : null
  } catch {
    return null
  }
}

export function clearSignupIntent(): void {
  if (typeof window === "undefined") return
  try {
    sessionStorage.removeItem(SIGNUP_INTENT_KEY)
  } catch {
    /* ignore */
  }
}

/**
 * Where new users go for profile setup.
 * Creator invite flow and explicit plan intent skip Choose Plan.
 */
export function resolveSignupProfileSetupPath(): "/choose-plan" | "/onboarding" {
  if (isCreatorFlowActive()) return "/onboarding"
  return getSignupIntent() ? "/onboarding" : "/choose-plan"
}

export function setCheckoutBillingInterval(interval: TraxProBillingIntervalId): void {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(CHECKOUT_BILLING_INTERVAL_KEY, interval)
  } catch {
    /* ignore */
  }
}

export function getCheckoutBillingInterval(): TraxProBillingIntervalId {
  if (typeof window === "undefined") return TRAXPRO_DEFAULT_BILLING_INTERVAL
  try {
    const raw = sessionStorage.getItem(CHECKOUT_BILLING_INTERVAL_KEY)
    return isTraxProBillingIntervalId(raw) ? raw : TRAXPRO_DEFAULT_BILLING_INTERVAL
  } catch {
    return TRAXPRO_DEFAULT_BILLING_INTERVAL
  }
}

export function clearCheckoutBillingInterval(): void {
  if (typeof window === "undefined") return
  try {
    sessionStorage.removeItem(CHECKOUT_BILLING_INTERVAL_KEY)
  } catch {
    /* ignore */
  }
}
