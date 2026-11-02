"use client"

import { useSyncExternalStore } from "react"
import { isMobileWebClipsImmersive, subscribeMobileWebClipsImmersive } from "@/lib/mobileWebClips"
import {
  trackMobileWebAppStoreClick,
  trackMobileWebOpenInAppClick,
} from "@/lib/mobileWebAppInstallAnalytics"
import { readConfiguredIosAppStoreUrl } from "@/lib/mobileWebOpenAppBanner"
import type { MobileWebOpenInAppLink as OpenInAppLink } from "@/lib/mobileWebOpenInApp"
import { MOBILE_WEB_TOUCH_MEDIA, isPhoneWebTouchTarget } from "@/lib/mobileWebTouch"

type Variant = "bar" | "inline" | "overlay"

function subscribePhoneWeb(onChange: () => void) {
  const media = window.matchMedia(MOBILE_WEB_TOUCH_MEDIA)
  media.addEventListener("change", onChange)
  window.addEventListener("resize", onChange)
  const observer = new MutationObserver(onChange)
  observer.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["class"],
  })
  return () => {
    media.removeEventListener("change", onChange)
    window.removeEventListener("resize", onChange)
    observer.disconnect()
  }
}

function phoneWebSnapshot() {
  if (!isPhoneWebTouchTarget()) return false
  const root = document.documentElement
  if (root.classList.contains("tt-native") || root.classList.contains("tt-native-ios")) {
    return false
  }
  return !/Capacitor|TradeTraxsNative/i.test(navigator.userAgent)
}

/**
 * User-activated universal link. Renders nothing on desktop, tablet, and native iOS.
 * App Store is a second link only when the official listing URL is configured.
 */
export default function MobileWebOpenInAppLink({
  link,
  variant = "bar",
  hideWhileClipsImmersive = false,
}: {
  link: OpenInAppLink | null
  variant?: Variant
  hideWhileClipsImmersive?: boolean
}) {
  const phoneWeb = useSyncExternalStore(
    subscribePhoneWeb,
    phoneWebSnapshot,
    () => false
  )
  const clipsImmersive = useSyncExternalStore(
    subscribeMobileWebClipsImmersive,
    isMobileWebClipsImmersive,
    () => false
  )
  if (!phoneWeb || !link) return null
  if (hideWhileClipsImmersive && clipsImmersive) return null

  const storeUrl = readConfiguredIosAppStoreUrl()
  const className =
    variant === "inline"
      ? "tt-mobile-web-open-in-app tt-mobile-web-open-in-app--inline"
      : variant === "overlay"
        ? "tt-mobile-web-open-in-app tt-mobile-web-open-in-app--overlay"
        : "tt-mobile-web-open-in-app tt-mobile-web-open-in-app--bar"

  return (
    <div className={className} role="navigation" aria-label="Open in the TradeTraxs app">
      <a
        href={link.href}
        onClick={(event) => {
          event.stopPropagation()
          trackMobileWebOpenInAppClick({
            contentKind: link.kind,
            uiVariant: variant,
          })
        }}
      >
        Open in App
      </a>
      {storeUrl ? (
        <a
          href={storeUrl}
          onClick={(event) => {
            event.stopPropagation()
            trackMobileWebAppStoreClick({ surface: "open_in_app" })
          }}
        >
          App Store
        </a>
      ) : null}
    </div>
  )
}
