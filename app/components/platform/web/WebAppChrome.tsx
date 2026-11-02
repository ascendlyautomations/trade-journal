"use client"

import { Suspense, type ReactNode } from "react"
import { usePathname, useSearchParams } from "next/navigation"
import MobileWebOpenInAppLink from "@/app/components/mobile/MobileWebOpenInAppLink"
import MobileWebTabBar from "@/app/components/mobile/MobileWebTabBar"
import { mobileWebOpenInAppLink } from "@/lib/mobileWebOpenInApp"

function MobileWebOpenInAppRoute() {
  const pathname = usePathname()
  const searchParams = useSearchParams()
  return (
    <MobileWebOpenInAppLink
      link={mobileWebOpenInAppLink(pathname || "/", searchParams.toString())}
      hideWhileClipsImmersive
    />
  )
}

/**
 * Web app chrome layout — identical to the previous AppChrome web branch
 * at 768px+. Phone adds a five-tab bar. Secondary titles live in the Navbar.
 */
export default function WebAppChrome({ children }: { children: ReactNode }) {
  return (
    <>
      {/* Navbar mounted by PlatformChrome via PlatformNavbar */}
      <div
        data-tt-app=""
        className="flex w-full flex-col pt-[var(--app-header-offset)] max-md:pb-[var(--app-tab-bar-offset)]"
      >
        <Suspense fallback={null}>
          <MobileWebOpenInAppRoute />
        </Suspense>
        {children}
      </div>
      <MobileWebTabBar />
    </>
  )
}
