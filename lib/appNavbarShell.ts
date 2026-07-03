import {
  isMarketingRoute,
  isPublicLegalRoute,
  isStandaloneFlowRoute,
} from "@/lib/authRoutes"

/** Routes that render PublicNavbar in their own layout — skip global app Navbar. */
export function shouldRenderGlobalAppNavbar(
  pathname: string | null | undefined,
): boolean {
  if (!pathname || isStandaloneFlowRoute(pathname)) return false
  if (isMarketingRoute(pathname) || isPublicLegalRoute(pathname)) return false
  if (pathname === "/demo" || pathname.startsWith("/demo/")) return false
  return true
}
