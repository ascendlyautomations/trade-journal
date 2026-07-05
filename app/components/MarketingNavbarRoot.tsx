import { headers } from "next/headers"
import { isStandaloneFlowRoute } from "@/lib/authRoutes"
import GlobalMarketingNavbar from "./GlobalMarketingNavbar"

/**
 * Server gate: auth/standalone routes never include marketing navbar in SSR HTML.
 * Client navigations are handled by GlobalMarketingNavbar layout-segment checks.
 */
export default async function MarketingNavbarRoot() {
  const pathname = (await headers()).get("x-pathname") ?? ""

  if (pathname && isStandaloneFlowRoute(pathname)) {
    return null
  }

  return <GlobalMarketingNavbar />
}
