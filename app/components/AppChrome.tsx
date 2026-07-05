"use client"

import { usePathname, useSelectedLayoutSegments } from "next/navigation"
import type { ReactNode } from "react"
import { shouldMountGlobalAppNavbar } from "@/lib/layoutChrome"
import Navbar from "./Navbar"

/**
 * Root app chrome: mounts the portaled app Navbar only on routes that need it.
 * Auth/marketing/legal/demo/standalone flows never mount Navbar (no CSS hiding).
 */
export default function AppChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const segments = useSelectedLayoutSegments()
  const showAppNavbar = shouldMountGlobalAppNavbar(pathname, segments)

  if (!showAppNavbar) {
    return <div className="flex w-full flex-col">{children}</div>
  }

  return (
    <>
      <Navbar />
      <div className="flex w-full flex-col pt-[var(--app-header-offset)]">
        {children}
      </div>
    </>
  )
}
