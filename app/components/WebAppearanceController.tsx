"use client"

import { useLayoutEffect } from "react"
import { usePathname } from "next/navigation"
import { applyWebAppearanceForPath } from "@/lib/webAppearance"

/** Re-applies appearance on client navigations, before the browser paints. */
export default function WebAppearanceController() {
  const pathname = usePathname()

  useLayoutEffect(() => {
    applyWebAppearanceForPath(pathname)
  }, [pathname])

  return null
}
