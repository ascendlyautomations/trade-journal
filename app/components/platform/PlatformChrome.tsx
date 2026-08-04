"use client"

import type { ReactNode } from "react"
import { usePathname, useSelectedLayoutSegments } from "next/navigation"
import { shouldMountGlobalAppNavbar } from "@/lib/layoutChrome"
import { isDmConversationPath } from "@/lib/messageRoutes"
import { usePlatformPresentation } from "./usePlatformPresentation"
import PlatformNavbar from "./PlatformNavbar"
import NativeIosAppChrome from "./native/NativeIosAppChrome"
import WebAppChrome from "./web/WebAppChrome"

/**
 * Root app chrome presentation adapter.
 *
 * Routing / mount rules unchanged from AppChrome:
 * - Auth/marketing/legal/demo/standalone: no navbar
 * - Native DM conversation: fullscreen (no navbar / tabs)
 * - Native iOS: scrollport + tab bar
 * - Web: padded content column
 */
export default function PlatformChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const segments = useSelectedLayoutSegments()
  const showAppNavbar = shouldMountGlobalAppNavbar(pathname, segments)
  const { isNativeIos } = usePlatformPresentation()
  const nativeDmFullscreen = isNativeIos && isDmConversationPath(pathname)

  if (!showAppNavbar) {
    return <div className="flex w-full flex-col">{children}</div>
  }

  if (nativeDmFullscreen) {
    return <div className="flex min-h-0 w-full flex-col">{children}</div>
  }

  if (isNativeIos) {
    return (
      <>
        <PlatformNavbar />
        <NativeIosAppChrome>{children}</NativeIosAppChrome>
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
