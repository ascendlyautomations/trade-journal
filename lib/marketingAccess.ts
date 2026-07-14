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

/**
 * Marketing navbar on public marketing / legal pages.
 *
 * Logged-out visitors (including mid-logout while auth is still resolving) must
 * ALWAYS see PublicNavbar — never a blank header. The app Navbar is intentionally
 * unmounted on these routes, so hiding PublicNavbar leaves no chrome at all.
 */
export function shouldShowMarketingNavbar(
  pathname: string | null | undefined,
  user: MarketingUser,
  profile: SubscriptionAccessProfile | null | undefined,
  loading: boolean,
): boolean {
  if (!pathname || isStandaloneFlowRoute(pathname)) return false
  if (!isMarketingRoute(pathname) && !isPublicLegalRoute(pathname)) {
    return false
  }

  // Visitors / post-logout: always show, even while auth loading flips during clear.
  if (!isAuthenticatedAppUser(user)) {
    return true
  }

  if (isSignupFlowActive()) return false

  // Only hide after auth has settled and we know the user still needs entry flow.
  // Do not hide while loading — that blanks the homepage during logout races.
  if (!loading && isInAppEntryFlow(user, profile, false)) {
    return false
  }

  // Members on marketing pages (or still hydrating): keep PublicNavbar visible.
  return true
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
