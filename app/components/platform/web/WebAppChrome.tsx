"use client"

import { Suspense, useEffect, type ReactNode } from "react"
import { usePathname, useSearchParams } from "next/navigation"
import MobileWebOpenInAppLink from "@/app/components/mobile/MobileWebOpenInAppLink"
import MobileWebTabBar from "@/app/components/mobile/MobileWebTabBar"
import MobileWebQuickTradeHost from "@/app/components/mobile/MobileWebQuickTradeHost"
import MobileWebGlobalUploadStatusBar from "@/app/components/mobile/upload/MobileWebGlobalUploadStatusBar"
import { mobileWebOpenInAppLink } from "@/lib/mobileWebOpenInApp"
import { syncMobileWebInAppHistory } from "@/lib/mobileWebInAppHistory"

function MobileWebOpenInAppRoute() {
  const pathname = usePathname()
  const searchParams = useSearchParams()
  const search = searchParams.toString()
  useEffect(() => {
    syncMobileWebInAppHistory(search ? `${pathname}?${search}` : pathname || "/")
  }, [pathname, search])
  return (
    <MobileWebOpenInAppLink
      link={mobileWebOpenInAppLink(pathname || "/", search)}
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
        className="flex w-full flex-col pt-[var(--app-header-offset)] max-md:pt-[calc(var(--app-header-offset)+var(--app-global-upload-offset,0px))] max-md:pb-[calc(var(--app-tab-bar-offset)+var(--app-live-session-chrome-offset,0px))]"
      >
        <MobileWebGlobalUploadStatusBar />
        <Suspense fallback={null}>
          <MobileWebOpenInAppRoute />
        </Suspense>
        {children}
      </div>
      <MobileWebTabBar />
      <MobileWebQuickTradeHost />
    </>
  )
}
