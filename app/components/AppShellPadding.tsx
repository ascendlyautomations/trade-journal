"use client"

import { usePathname } from "next/navigation"
import type { ReactNode } from "react"
import { isStandaloneFlowRoute } from "@/lib/authRoutes"

export default function AppShellPadding({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const standaloneFlow = isStandaloneFlowRoute(pathname)

  return (
    <div
      className={
        standaloneFlow
          ? "flex w-full flex-col"
          : "flex w-full flex-col pt-[var(--app-header-offset)]"
      }
    >
      {children}
    </div>
  )
}
