import {
  isAuthRoute,
  isMarketingRoute,
  isPublicLegalRoute,
  isStandaloneFlowRoute,
} from "./authRoutes.ts"

/**
 * Routes where authenticated app data warm (Dashboard RPC, profile Realtime)
 * should not run — marketing/legal/auth shells only need Auth session discovery.
 */
export function shouldWarmAppDataCachesForPath(
  pathname: string | null | undefined
): boolean {
  if (!pathname) return false
  if (isStandaloneFlowRoute(pathname)) return false
  if (isMarketingRoute(pathname)) return false
  if (isPublicLegalRoute(pathname)) return false
  if (pathname === "/demo" || pathname.startsWith("/demo/")) return false
  if (pathname === "/marketing" || pathname.startsWith("/marketing/")) {
    return false
  }
  return true
}

/** True for auth pages where no app-table queries should run before sign-in. */
export function isPreAuthShellPath(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return isAuthRoute(pathname)
}
