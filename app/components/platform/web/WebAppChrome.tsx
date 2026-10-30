"use client"

import type { ReactNode } from "react"
import MobileWebTabBar from "@/app/components/mobile/MobileWebTabBar"
import MobileWebPageHeader from "@/app/components/mobile/MobileWebPageHeader"

/**
 * Web app chrome layout — identical to the previous AppChrome web branch
 * at 768px+. Phone adds a five-tab bar and secondary page header only.
 */
export default function WebAppChrome({ children }: { children: ReactNode }) {
  return (
    <>
      {/* Navbar mounted by PlatformChrome via PlatformNavbar */}
      <div
        data-tt-app=""
        className="flex w-full flex-col pt-[var(--app-header-offset)] max-md:pb-[var(--app-tab-bar-offset)]"
      >
        <MobileWebPageHeader />
        {children}
      </div>
      <MobileWebTabBar />
    </>
  )
}
