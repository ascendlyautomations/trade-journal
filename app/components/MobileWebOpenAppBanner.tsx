"use client"

import { useEffect, useState } from "react"
import { usePathname } from "next/navigation"
import { isNativeIos } from "@/lib/nativePlatform"
import {
  canonicalMobileWebOpenAppURL,
  dismissMobileWebOpenAppBanner,
  isIosSafariMobileUserAgent,
  isMobileWebOpenAppBannerDismissed,
} from "@/lib/mobileWebOpenAppBanner"

/**
 * Slim iPhone/iPad Safari prompt. Open App is the current page as an HTTPS
 * universal link. Dismiss hides it for this browser session only.
 */
export default function MobileWebOpenAppBanner() {
  const pathname = usePathname()
  const [href, setHref] = useState<string | null>(null)

  useEffect(() => {
    if (typeof window === "undefined") return
    if (isNativeIos() || !isIosSafariMobileUserAgent(navigator.userAgent)) {
      setHref(null)
      return
    }
    if (pathname === "/marketing" || pathname?.startsWith("/marketing/")) {
      setHref(null)
      return
    }
    if (isMobileWebOpenAppBannerDismissed(window.sessionStorage)) {
      setHref(null)
      return
    }
    setHref(canonicalMobileWebOpenAppURL(pathname || "/", window.location.search))
  }, [pathname])

  if (!href) return null

  return (
    <div
      className="fixed inset-x-0 top-0 z-[10050] border-b border-white/10 bg-[#0b1f3a]/95 pt-[env(safe-area-inset-top)] text-white shadow-[0_8px_24px_rgba(0,0,0,0.28)] backdrop-blur-md"
      role="region"
      aria-label="Open TradeTraxs app"
    >
      <div className="mx-auto flex h-11 max-w-6xl items-center gap-2 px-3">
        <p className="min-w-0 flex-1 truncate text-sm font-semibold">TradeTraxs</p>
        <a
          href={href}
          className="inline-flex h-11 shrink-0 items-center px-3 text-sm font-semibold text-blue-300"
        >
          Open App
        </a>
        <button
          type="button"
          aria-label="Dismiss"
          className="inline-flex h-11 w-11 shrink-0 items-center justify-center text-lg leading-none text-white/80"
          onClick={(event) => {
            event.preventDefault()
            event.stopPropagation()
            dismissMobileWebOpenAppBanner(window.sessionStorage)
            setHref(null)
          }}
        >
          ×
        </button>
      </div>
    </div>
  )
}
