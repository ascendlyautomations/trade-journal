/**
 * Native-shell detection without Capacitor.
 *
 * Markers (legacy WKWebView / cookie from `/native`, custom UA):
 * - cookie `tt_native=1`
 * - User-Agent containing `TradeTraxsNative`
 *
 * The supported iOS app is Swift under `native-ios/` and does not embed Cap.
 */
export function isNativePlatform(): boolean {
  if (typeof window === "undefined") return false
  if (/(?:^|;\s*)tt_native=1(?:;|$)/.test(document.cookie)) return true
  return /TradeTraxsNative/i.test(navigator.userAgent)
}

/** Historical Cap API — TradeTraxs native shell is iOS-only when present. */
export function getNativePlatform(): string {
  return isNativePlatform() ? "ios" : "web"
}

/** True when the page is running inside the native iOS shell markers. */
export function isNativeIos(): boolean {
  return isNativePlatform()
}
