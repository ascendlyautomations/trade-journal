import {
  isMarketingRoute,
  isPublicLegalRoute,
  isStandaloneFlowRoute,
} from "@/lib/authRoutes"
import { shouldRenderGlobalAppNavbar } from "@/lib/appNavbarShell"

/** App route segments that must never mount marketing or app nav chrome. */
export const STANDALONE_LAYOUT_SEGMENTS = new Set([
  "login",
  "reset-password",
  /** Creator invite auth + redeem — never show marketing Login/Sign Up. */
  "creator",
  "onboarding",
  "choose-plan",
  "finish-trial",
  /** Instagram / export ad frames — no marketing or app chrome. */
  "marketing",
])

export function isStandaloneLayoutSegment(segments: readonly string[]): boolean {
  return segments.some((segment) => STANDALONE_LAYOUT_SEGMENTS.has(segment))
}

export function shouldMountMarketingNavbar(
  pathname: string | null | undefined,
  segments: readonly string[],
): boolean {
  if (isStandaloneFlowRoute(pathname)) return false
  // Pathname is authoritative for marketing/legal pages. After client nav from
  // /login → /, layout segments can briefly (or stuck) still include "login",
  // which would unmount PublicNavbar entirely on the homepage.
  if (
    pathname &&
    (isMarketingRoute(pathname) || isPublicLegalRoute(pathname))
  ) {
    return true
  }
  if (isStandaloneLayoutSegment(segments)) return false
  return true
}

export function shouldMountGlobalAppNavbar(
  pathname: string | null | undefined,
  segments: readonly string[],
): boolean {
  if (isStandaloneLayoutSegment(segments)) return false
  return shouldRenderGlobalAppNavbar(pathname)
}
