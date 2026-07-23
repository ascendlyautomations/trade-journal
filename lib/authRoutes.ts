/** Auth pages — login, password reset, creator invite auth. */
export const AUTH_ROUTE_PREFIXES = ["/login", "/reset-password", "/creator"] as const

/** Profile setup before app access. */
export const ONBOARDING_ROUTE_PREFIXES = ["/onboarding", "/choose-plan"] as const

/** Stripe checkout step after profile setup. */
export const PRE_CHECKOUT_ROUTE_PREFIXES = ["/finish-trial"] as const

/** Marketing site pages (logged-out experience). */
export const MARKETING_EXACT_PATHS = [
  "/",
  "/faq",
  "/pricing",
  "/about",
  "/legal",
  "/community-guidelines",
  "/creator-guidelines",
  "/affiliate",
  "/contact",
] as const

/** Legal pages that share the marketing navbar when logged out. */
export const PUBLIC_LEGAL_EXACT_PATHS = [
  "/privacy",
  "/terms",
  "/refund-policy",
  "/cookie-policy",
  "/acceptable-use",
] as const

function matchesPrefix(pathname: string, prefixes: readonly string[]): boolean {
  return prefixes.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  )
}

export function isAuthRoute(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return matchesPrefix(pathname, AUTH_ROUTE_PREFIXES)
}

export function isLoginRoute(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return pathname === "/login"
}

export function isOnboardingRoute(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return matchesPrefix(pathname, ONBOARDING_ROUTE_PREFIXES)
}

export function isPreCheckoutRoute(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return matchesPrefix(pathname, PRE_CHECKOUT_ROUTE_PREFIXES)
}

/**
 * Signup → onboarding → checkout flow.
 * No marketing navbar, demo banner, or app header offset.
 */
export function isStandaloneFlowRoute(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return (
    pathname === "/native" ||
    isAuthRoute(pathname) ||
    isOnboardingRoute(pathname) ||
    isPreCheckoutRoute(pathname)
  )
}

export function isMarketingRoute(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return MARKETING_EXACT_PATHS.includes(
    pathname as (typeof MARKETING_EXACT_PATHS)[number],
  )
}

export function isPublicLegalRoute(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return PUBLIC_LEGAL_EXACT_PATHS.includes(
    pathname as (typeof PUBLIC_LEGAL_EXACT_PATHS)[number],
  )
}
