"use client"

import type { ReactNode } from "react"
import { usePathname, useSelectedLayoutSegments } from "next/navigation"
import { shouldMountGlobalAppNavbar } from "@/lib/layoutChrome"
import { isAppAddTradePath } from "@/lib/addTradePath"
import { isAppCalendarPath } from "@/lib/calendarPath"
import { isAppDashboardPath } from "@/lib/dashboardPath"
import { isAppFeedPath } from "@/lib/feedPath"
import { isAppMessagesInboxPath } from "@/lib/messagesPath"
import { isAppTradesPath } from "@/lib/tradesPath"
import { isDmConversationPath } from "@/lib/messageRoutes"
import { usePlatformPresentation } from "./usePlatformPresentation"
import PlatformNavbar from "./PlatformNavbar"
import NativeIosAppChrome from "./native/NativeIosAppChrome"
import WebAppChrome from "./web/WebAppChrome"

/**
 * Root app chrome presentation adapter.
 *
 * Native iOS tab roots (Dashboard / Feed / Calendar / Trades / Messages /
 * Add Trade): hide the website Navbar; pad with safe-area-top only.
 */
export default function PlatformChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const segments = useSelectedLayoutSegments()
  const showAppNavbar = shouldMountGlobalAppNavbar(pathname, segments)
  const { isNativeIos } = usePlatformPresentation()
  const nativeDmFullscreen = isNativeIos && isDmConversationPath(pathname)
  const nativeNoWebNavbar =
    isNativeIos &&
    (isAppDashboardPath(pathname) ||
      isAppFeedPath(pathname) ||
      isAppCalendarPath(pathname) ||
      isAppTradesPath(pathname) ||
      isAppMessagesInboxPath(pathname) ||
      isAppAddTradePath(pathname))

  if (!showAppNavbar) {
    return <div className="flex w-full flex-col">{children}</div>
  }

  if (nativeDmFullscreen) {
    return <div className="flex min-h-0 w-full flex-col">{children}</div>
  }

  if (isNativeIos) {
    return (
      <>
        {nativeNoWebNavbar ? null : <PlatformNavbar />}
        <NativeIosAppChrome safeAreaOnlyTopInset={nativeNoWebNavbar}>
          {children}
        </NativeIosAppChrome>
      </>
    )
  }

  return (
    <>
      <PlatformNavbar />
      <WebAppChrome>{children}</WebAppChrome>
    </>
  )
}
