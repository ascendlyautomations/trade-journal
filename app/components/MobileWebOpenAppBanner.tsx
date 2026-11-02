"use client"

import { useEffect, useLayoutEffect, useRef, useState } from "react"
import {
  MOBILE_WEB_CLIPS_IMMERSIVE_CLASS,
  isMobileWebClipsImmersive,
  subscribeMobileWebClipsImmersive,
} from "@/lib/mobileWebClips"
import { MOBILE_WEB_TOUCH_MEDIA, isPhoneWebTouchTarget } from "@/lib/mobileWebTouch"
import {
  trackMobileWebGetAppBannerClick,
  trackMobileWebGetAppBannerDismiss,
  trackMobileWebGetAppBannerImpression,
  trackMobileWebAppStoreClick,
} from "@/lib/mobileWebAppInstallAnalytics"
import {
  MOBILE_WEB_GET_APP_BANNER_AWAY_CLASS,
  MOBILE_WEB_GET_APP_BANNER_CLASS,
  appBannerNavbarShiftPx,
  dismissMobileWebGetAppBanner,
  isEmbeddedAppShell,
  isFullscreenMediaOpen,
  isMobileWebGetAppBannerDismissed,
  readConfiguredIosAppStoreUrl,
  shouldShowMobileWebGetAppBanner,
} from "@/lib/mobileWebOpenAppBanner"

function hasCapacitorBridge(): boolean {
  if (typeof window === "undefined") return false
  return "Capacitor" in window
}

/**
 * Compact App Store promo for phone web. Renders nothing until
 * NEXT_PUBLIC_IOS_APP_STORE_URL is configured. Sits in normal flow above
 * the fixed navbar and scrolls away with the page.
 */
export default function MobileWebOpenAppBanner() {
  const appStoreUrl = readConfiguredIosAppStoreUrl()
  const bannerRef = useRef<HTMLDivElement>(null)
  const [shown, setShown] = useState(false)

  useEffect(() => {
    if (!appStoreUrl) return
    const update = () => {
      const root = document.documentElement
      setShown(
        shouldShowMobileWebGetAppBanner({
          appStoreUrl,
          dismissed: isMobileWebGetAppBannerDismissed(window.localStorage),
          phoneWeb: isPhoneWebTouchTarget(),
          embeddedShell: isEmbeddedAppShell({
            htmlClassName: root.className,
            userAgent: navigator.userAgent,
            hasCapacitor: hasCapacitorBridge(),
          }),
          clipsImmersive:
            isMobileWebClipsImmersive() ||
            root.classList.contains(MOBILE_WEB_CLIPS_IMMERSIVE_CLASS),
          fullscreenMedia: isFullscreenMediaOpen(document),
        })
      )
    }
    update()
    const media = window.matchMedia(MOBILE_WEB_TOUCH_MEDIA)
    media.addEventListener("change", update)
    window.addEventListener("resize", update)
    const unsubscribeClips = subscribeMobileWebClipsImmersive(update)
    document.addEventListener("fullscreenchange", update)
    document.addEventListener("webkitfullscreenchange", update)
    const observer = new MutationObserver(update)
    observer.observe(document.body, { childList: true })
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class"],
    })
    return () => {
      media.removeEventListener("change", update)
      window.removeEventListener("resize", update)
      unsubscribeClips()
      document.removeEventListener("fullscreenchange", update)
      document.removeEventListener("webkitfullscreenchange", update)
      observer.disconnect()
    }
  }, [appStoreUrl])

  useLayoutEffect(() => {
    const root = document.documentElement
    if (!shown) {
      root.classList.remove(
        MOBILE_WEB_GET_APP_BANNER_CLASS,
        MOBILE_WEB_GET_APP_BANNER_AWAY_CLASS
      )
      root.style.removeProperty("--tt-app-banner-shift")
      return
    }

    const sync = () => {
      const height = bannerRef.current?.offsetHeight ?? 0
      const shift = appBannerNavbarShiftPx(height, window.scrollY)
      root.style.setProperty("--tt-app-banner-shift", `${shift}px`)
      root.classList.add(MOBILE_WEB_GET_APP_BANNER_CLASS)
      root.classList.toggle(
        MOBILE_WEB_GET_APP_BANNER_AWAY_CLASS,
        height > 0 && shift === 0
      )
    }
    sync()
    window.addEventListener("scroll", sync, { passive: true })
    window.addEventListener("resize", sync)
    return () => {
      window.removeEventListener("scroll", sync)
      window.removeEventListener("resize", sync)
      root.classList.remove(
        MOBILE_WEB_GET_APP_BANNER_CLASS,
        MOBILE_WEB_GET_APP_BANNER_AWAY_CLASS
      )
      root.style.removeProperty("--tt-app-banner-shift")
    }
  }, [shown])

  useEffect(() => {
    if (!shown) return
    trackMobileWebGetAppBannerImpression()
  }, [shown])

  if (!appStoreUrl || !shown) return null

  return (
    <div
      ref={bannerRef}
      className="tt-mobile-web-app-banner"
      role="region"
      aria-label="Get the TradeTraxs app"
    >
      <div className="tt-mobile-web-app-banner__row">
        <img
          src="/logo.png"
          alt=""
          width={40}
          height={40}
          className="tt-mobile-web-app-banner__icon"
          decoding="async"
        />
        <div className="tt-mobile-web-app-banner__copy">
          <p className="tt-mobile-web-app-banner__name">TradeTraxs</p>
          <p className="tt-mobile-web-app-banner__desc">Trading journal & community</p>
        </div>
        <a
          className="tt-mobile-web-app-banner__cta"
          href={appStoreUrl}
          onClick={() => {
            trackMobileWebGetAppBannerClick()
            trackMobileWebAppStoreClick({ surface: "get_app_banner" })
          }}
        >
          Get App
        </a>
        <button
          type="button"
          className="tt-mobile-web-app-banner__close"
          aria-label="Dismiss Get App banner"
          onClick={() => {
            trackMobileWebGetAppBannerDismiss()
            dismissMobileWebGetAppBanner(window.localStorage)
            setShown(false)
          }}
        >
          <svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true">
            <path
              d="M2 2l8 8M10 2L2 10"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
            />
          </svg>
        </button>
      </div>
    </div>
  )
}
