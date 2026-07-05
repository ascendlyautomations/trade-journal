"use client"

import { usePathname, useSelectedLayoutSegments } from "next/navigation"
import PublicNavbar from "./PublicNavbar"
import { shouldMountMarketingNavbar } from "@/lib/layoutChrome"

/**
 * Root-mounted marketing navbar. Uses layout segments + pathname so auth routes
 * never mount PublicNavbar — including during the first client navigation from /.
 */
export default function GlobalMarketingNavbar() {
  const pathname = usePathname()
  const segments = useSelectedLayoutSegments()

  if (!shouldMountMarketingNavbar(pathname, segments)) {
    return null
  }

  return <PublicNavbar />
}
