"use client"

import type { ReactNode } from "react"

/**
 * Web app chrome layout — identical to the previous AppChrome web branch.
 */
export default function WebAppChrome({ children }: { children: ReactNode }) {
  return (
    <>
      {/* Navbar mounted by PlatformChrome via PlatformNavbar */}
      <div className="flex w-full flex-col pt-[var(--app-header-offset)]">
        {children}
      </div>
    </>
  )
}
