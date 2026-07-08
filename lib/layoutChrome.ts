import { isStandaloneFlowRoute } from "@/lib/authRoutes"
import { shouldRenderGlobalAppNavbar } from "@/lib/appNavbarShell"

/** App route segments that must never mount marketing or app nav chrome. */
export const STANDALONE_LAYOUT_SEGMENTS = new Set([
  "login",
  "reset-password",
  "onboarding",
  "choose-plan",
  "finish-trial",
])

export function isStandaloneLayoutSegment(segments: readonly string[]): boolean {
  return segments.some((segment) => STANDALONE_LAYOUT_SEGMENTS.has(segment))
}

export function shouldMountMarketingNavbar(
  pathname: string | null | undefined,
  segments: readonly string[],
): boolean {
  if (isStandaloneLayoutSegment(segments)) return false
  if (isStandaloneFlowRoute(pathname)) return false
  return true
}

export function shouldMountGlobalAppNavbar(
  pathname: string | null | undefined,
  segments: readonly string[],
): boolean {
  if (isStandaloneLayoutSegment(segments)) return false
  return shouldRenderGlobalAppNavbar(pathname)
}
