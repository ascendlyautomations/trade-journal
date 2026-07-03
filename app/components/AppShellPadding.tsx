"use client"

import { usePathname } from "next/navigation"
import type { ReactNode } from "react"
import { shouldRenderGlobalAppNavbar } from "@/lib/appNavbarShell"

/**
 * Reserves vertical space for the fixed global app Navbar only.
 * Marketing/legal routes render PublicNavbar and apply their own offset
 * (e.g. COMPANY_PAGE_TOP) — do not double-pad here.
 */
export default function AppShellPadding({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const reserveNavbarSpace = shouldRenderGlobalAppNavbar(pathname)

  return (
    <div
      className={
        reserveNavbarSpace
          ? "flex w-full flex-col pt-[var(--app-header-offset)]"
          : "flex w-full flex-col"
      }
    >
      {children}
    </div>
  )
}
