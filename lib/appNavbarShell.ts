import {
  isMarketingRoute,
  isPublicLegalRoute,
  isStandaloneFlowRoute,
} from "@/lib/authRoutes"

/** True when the route must not mount the global app Navbar or reserve header offset. */
export function shouldOptOutOfGlobalAppNavbar(
  pathname: string | null | undefined,
): boolean {
  if (!pathname) return true
  return (
    isStandaloneFlowRoute(pathname) ||
    isMarketingRoute(pathname) ||
    isPublicLegalRoute(pathname) ||
    pathname === "/demo" ||
    pathname.startsWith("/demo/")
  )
}

/** Routes that render PublicNavbar in their own layout — skip global app Navbar. */
export function shouldRenderGlobalAppNavbar(
  pathname: string | null | undefined,
): boolean {
  if (shouldOptOutOfGlobalAppNavbar(pathname)) return false
  return true
}
