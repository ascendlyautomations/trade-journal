import { isDemoUserId } from "@/lib/demo/constants"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import {
  hasActiveMembership,
  needsSubscriptionCheckout,
  type SubscriptionAccessProfile,
} from "@/lib/subscriptionAccess"
import { isMarketingRoute, isPublicLegalRoute, isStandaloneFlowRoute } from "@/lib/authRoutes"
import { isSignupFlowActive } from "@/lib/signupFlow"

type MarketingUser = { id: string } | null | undefined

export function isAuthenticatedAppUser(user: MarketingUser): boolean {
  return !!user && !isDemoUserId(user.id)
}

/** Authenticated user still completing signup → onboarding → checkout. */
export function isInAppEntryFlow(
  user: MarketingUser,
  profile: SubscriptionAccessProfile | null | undefined,
  loading: boolean,
): boolean {
  if (isSignupFlowActive()) return true
  if (!isAuthenticatedAppUser(user)) return false
  if (loading && !profile) return true
  if (!profile) return true
  return profileNeedsOnboarding(profile) || needsSubscriptionCheckout(profile)
}

/** Logged-out marketing navbar on public marketing pages only. */
export function shouldShowMarketingNavbar(
  pathname: string | null | undefined,
  user: MarketingUser,
  profile: SubscriptionAccessProfile | null | undefined,
  loading: boolean,
): boolean {
  if (!pathname || isStandaloneFlowRoute(pathname)) return false
  if (isSignupFlowActive()) return false
  if (isInAppEntryFlow(user, profile, loading)) return false
  if (user || loading) return false
  return isMarketingRoute(pathname) || isPublicLegalRoute(pathname)
}

export function hasCompletedAppEntry(
  user: MarketingUser,
  profile: SubscriptionAccessProfile | null | undefined,
): boolean {
  return isAuthenticatedAppUser(user) && hasActiveMembership(profile)
}

/** Same condition as PublicNavbar "Return to App" chrome — single membership source of truth. */
export function shouldShowCustomerHomeChrome(
  user: MarketingUser,
  profile: SubscriptionAccessProfile | null | undefined,
  loading: boolean,
): boolean {
  return (
    isAuthenticatedAppUser(user) &&
    !loading &&
    !!profile &&
    hasActiveMembership(profile)
  )
}
