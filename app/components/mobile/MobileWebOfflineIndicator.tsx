"use client"

import { useSyncExternalStore } from "react"
import { MOBILE_WEB_OFFLINE_LABEL } from "@/lib/mobileWebNetworkRecovery"
import { MOBILE_WEB_TOUCH_MEDIA } from "@/lib/mobileWebTouch"

function subscribeOnline(onChange: () => void) {
  window.addEventListener("online", onChange)
  window.addEventListener("offline", onChange)
  return () => {
    window.removeEventListener("online", onChange)
    window.removeEventListener("offline", onChange)
  }
}

function onlineSnapshot() {
  return typeof navigator !== "undefined" ? navigator.onLine : true
}

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
  if (!window.matchMedia(MOBILE_WEB_TOUCH_MEDIA).matches) return false
  const root = document.documentElement
  if (root.classList.contains("tt-native-ios") || root.classList.contains("tt-native")) {
    return false
  }
  return !/Capacitor|TradeTraxsNative/i.test(navigator.userAgent)
}

/** Phone web only — fixed strip under the app header when the browser is offline. */
export default function MobileWebOfflineIndicator() {
  const online = useSyncExternalStore(subscribeOnline, onlineSnapshot, () => true)
  const phoneWeb = useSyncExternalStore(
    subscribePhoneWeb,
    phoneWebSnapshot,
    () => false
  )
  if (!phoneWeb || online) return null

  return (
    <div
      className="tt-mobile-web-offline-indicator"
      role="status"
      aria-live="polite"
    >
      {MOBILE_WEB_OFFLINE_LABEL}
    </div>
  )
}
