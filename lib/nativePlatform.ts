import { Capacitor } from "@capacitor/core"

/**
 * Single entry point for native-shell detection.
 * Prefer this over scattering Capacitor.isNativePlatform() calls.
 */
export function isNativePlatform(): boolean {
  if (typeof window === "undefined") return false
  try {
    if (Capacitor.isNativePlatform()) return true
  } catch {
    // Capacitor bridge may be unavailable during SSR/prerender.
  }
  // Hosted WebView markers: cookie set by /native, custom UA token from
  // capacitor.config appendUserAgent. Do NOT test for window.Capacitor —
  // the bundled @capacitor/core defines that global on the web too.
  if (/(?:^|;\s*)tt_native=1(?:;|$)/.test(document.cookie)) return true
  return /TradeTraxsNative/i.test(navigator.userAgent)
}

export function getNativePlatform(): string {
  try {
    return Capacitor.getPlatform()
  } catch {
    return "web"
  }
}

/** Capacitor iOS shell only — false on web, Android, and desktop. */
export function isNativeIos(): boolean {
  return isNativePlatform() && getNativePlatform() === "ios"
}
