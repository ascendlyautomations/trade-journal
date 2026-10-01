/** Session-only dismissal for the mobile web Open App prompt. Not an account setting. */
export const MOBILE_WEB_OPEN_APP_BANNER_SESSION_KEY = "tt.mobileWebOpenAppBanner.dismissed"

export function isIosSafariMobileUserAgent(userAgent: string): boolean {
  if (/TradeTraxsNative/i.test(userAgent)) return false
  return /iPhone|iPad|iPod/i.test(userAgent)
}

/** HTTPS universal link on the canonical host. Path and query only — no custom scheme. */
export function canonicalMobileWebOpenAppURL(pathname: string, search = ""): string {
  const path = pathname.startsWith("/") ? pathname : `/${pathname}`
  const query = search
    ? search.startsWith("?")
      ? search
      : `?${search}`
    : ""
  return `https://www.tradetraxs.com${path}${query}`
}

export function isMobileWebOpenAppBannerDismissed(
  storage: { getItem(key: string): string | null } | null
): boolean {
  if (!storage) return false
  return storage.getItem(MOBILE_WEB_OPEN_APP_BANNER_SESSION_KEY) === "1"
}

export function dismissMobileWebOpenAppBanner(
  storage: { setItem(key: string, value: string): void } | null
): void {
  storage?.setItem(MOBILE_WEB_OPEN_APP_BANNER_SESSION_KEY, "1")
}
