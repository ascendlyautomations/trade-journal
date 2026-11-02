/**
 * Phone-web "Get the App" banner.
 * Hidden until NEXT_PUBLIC_IOS_APP_STORE_URL is an https apps.apple.com listing.
 * Dismissal lives in localStorage for 30 days. Not an account setting.
 */

export const MOBILE_WEB_GET_APP_BANNER_STORAGE_KEY =
  "tt.mobileWebGetAppBanner.dismissedAt"

/** Hide for at least this long after the close button. */
export const MOBILE_WEB_GET_APP_DISMISS_MS = 30 * 24 * 60 * 60 * 1000

export const MOBILE_WEB_GET_APP_BANNER_CLASS = "tt-mobile-web-app-banner-on"

export const MOBILE_WEB_GET_APP_BANNER_AWAY_CLASS =
  "tt-mobile-web-app-banner-away"

export const MOBILE_WEB_FULLSCREEN_MEDIA_SELECTOR = [
  '[aria-label="Stories"]',
  '[aria-label="Clip viewer"]',
  '[aria-label="Image viewer"]',
].join(", ")

const APP_STORE_HOSTS = new Set(["apps.apple.com", "itunes.apple.com"])

type KeyValueStore = {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

/** Official listing only. Empty, relative, and non-store URLs stay disabled. */
export function configuredIosAppStoreUrl(
  raw: string | undefined | null
): string | null {
  const trimmed = raw?.trim() ?? ""
  if (!trimmed) return null
  let url: URL
  try {
    url = new URL(trimmed)
  } catch {
    return null
  }
  if (url.protocol !== "https:") return null
  if (url.username || url.password) return null
  if (!APP_STORE_HOSTS.has(url.hostname)) return null
  if (!url.pathname || url.pathname === "/") return null
  return url.toString()
}

export function readConfiguredIosAppStoreUrl(): string | null {
  return configuredIosAppStoreUrl(process.env.NEXT_PUBLIC_IOS_APP_STORE_URL)
}

export function isMobileWebGetAppBannerDismissed(
  storage: { getItem(key: string): string | null } | null,
  now = Date.now()
): boolean {
  if (!storage) return false
  const raw = storage.getItem(MOBILE_WEB_GET_APP_BANNER_STORAGE_KEY)
  if (!raw) return false
  const dismissedAt = Number(raw)
  if (!Number.isFinite(dismissedAt)) return false
  return now - dismissedAt < MOBILE_WEB_GET_APP_DISMISS_MS
}

export function dismissMobileWebGetAppBanner(
  storage: KeyValueStore | null,
  now = Date.now()
): void {
  storage?.setItem(MOBILE_WEB_GET_APP_BANNER_STORAGE_KEY, String(now))
}

export function isEmbeddedAppShell(input: {
  htmlClassName: string
  userAgent: string
  hasCapacitor: boolean
}): boolean {
  if (input.hasCapacitor) return true
  if (/(?:^|\s)tt-native(?:-ios)?(?:\s|$)/.test(input.htmlClassName)) return true
  return /TradeTraxsNative|Capacitor/i.test(input.userAgent)
}

export function isFullscreenMediaOpen(doc: {
  fullscreenElement: unknown
  querySelector(selector: string): unknown
}): boolean {
  if (doc.fullscreenElement) return true
  return Boolean(doc.querySelector(MOBILE_WEB_FULLSCREEN_MEDIA_SELECTOR))
}

export function shouldShowMobileWebGetAppBanner(input: {
  appStoreUrl: string | null
  dismissed: boolean
  phoneWeb: boolean
  embeddedShell: boolean
  clipsImmersive: boolean
  fullscreenMedia: boolean
}): boolean {
  if (!input.appStoreUrl) return false
  if (input.dismissed || !input.phoneWeb) return false
  if (input.embeddedShell || input.clipsImmersive || input.fullscreenMedia) {
    return false
  }
  return true
}

/** Pixels of banner still between the viewport top and the fixed navbar. */
export function appBannerNavbarShiftPx(
  bannerHeight: number,
  scrollY: number
): number {
  if (bannerHeight <= 0) return 0
  const scrolled = scrollY > 0 ? scrollY : 0
  const remain = bannerHeight - scrolled
  return remain > 0 ? remain : 0
}
