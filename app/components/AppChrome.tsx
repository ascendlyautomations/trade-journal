"use client"

import { usePathname } from "next/navigation"
import type { ReactNode } from "react"
import { shouldRenderGlobalAppNavbar } from "@/lib/appNavbarShell"
import Navbar from "./Navbar"

/**
 * Root app chrome: mounts the portaled app Navbar only on routes that need it.
 * Auth/marketing/legal/demo/standalone flows never mount Navbar (no CSS hiding).
 */
export default function AppChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const showAppNavbar = shouldRenderGlobalAppNavbar(pathname)

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
