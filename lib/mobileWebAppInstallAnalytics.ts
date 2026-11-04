/**
 * Lightweight mobile-web app-install promotion analytics.
 *
 * Transport: Vercel Web Analytics custom events (`track` from `@vercel/analytics`),
 * loaded in production on Vercel when the user accepts analytics cookies
 * (`NativeAwareVercelInsights` + `isAnalyticsAllowed()`). No new backend or schema.
 *
 * Payload rules: coarse enums only — no user ids, trade/post ids, profile handles,
 * URLs, or P&L.
 *
 * Measurable in Vercel Web Analytics (with consent + deployed Analytics script):
 * - Get App banner impression (once per browser tab session while eligible)
 * - Get App CTA click
 * - Get App banner dismiss
 * - Open in App universal-link tap (content kind + UI variant)
 * - App Store listing taps from instrumented phone-web surfaces
 *
 * Not attributable without additional infrastructure:
 * - iOS app install or first open after store visit
 * - Whether a universal link opened the native app vs stayed in Safari
 * - App Store product page views after the user leaves the site
 * - Smart App Banner (`apple-itunes-app`) impressions or taps (not instrumented)
 * - Get App banner when `NEXT_PUBLIC_IOS_APP_STORE_URL` is unset (banner hidden)
 * - Events on localhost / non-Vercel hosts unless Analytics is injected manually
 */

import { isAnalyticsAllowed } from "./cookieConsent.ts"
import { isEmbeddedAppShell } from "./mobileWebOpenAppBanner.ts"
import type { MobileWebOpenInAppKind } from "./mobileWebOpenInApp.ts"
import { isPhoneWebTouchTarget } from "./mobileWebTouch.ts"

export const MOBILE_WEB_GET_APP_BANNER_IMPRESSION_SESSION_KEY =
  "tt.mobileWebGetAppBanner.analyticsImpression"

export const MOBILE_WEB_APP_INSTALL_EVENTS = {
  getAppBannerImpression: "Mobile Web Get App Banner Impression",
  getAppBannerClick: "Mobile Web Get App Banner Click",
  getAppBannerDismiss: "Mobile Web Get App Banner Dismiss",
  openInAppClick: "Mobile Web Open In App Click",
  appStoreClick: "Mobile Web App Store Click",
} as const

export type MobileWebOpenInAppUiVariant = "bar" | "inline" | "overlay"

export type MobileWebAppStorePromoSurface =
  | "get_app_banner"
  | "open_in_app"
  | "community_room_invite"
  | "hero"
  | "nav"
  | "ios_section"
  | "final_cta"

type AllowedTrackValue = string | number | boolean | null | undefined

type TrackFn = (
  name: string,
  properties?: Record<string, AllowedTrackValue>
) => void

type SessionStore = {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

export function shouldSendMobileWebAppInstallAnalytics(input: {
  phoneWeb: boolean
  embeddedShell: boolean
  analyticsAllowed: boolean
}): boolean {
  if (!input.analyticsAllowed || !input.phoneWeb) return false
  if (input.embeddedShell) return false
  return true
}

export function mobileWebAppInstallAnalyticsContext(input?: {
  phoneWeb?: boolean
  htmlClassName?: string
  userAgent?: string
  hasCapacitor?: boolean
  analyticsAllowed?: boolean
}): {
  phoneWeb: boolean
  embeddedShell: boolean
  analyticsAllowed: boolean
  canSend: boolean
} {
  const phoneWeb = input?.phoneWeb ?? isPhoneWebTouchTarget()
  const htmlClassName =
    input?.htmlClassName ??
    (typeof document !== "undefined" ? document.documentElement.className : "")
  const userAgent =
    input?.userAgent ??
    (typeof navigator !== "undefined" ? navigator.userAgent : "")
  const hasCapacitor =
    input?.hasCapacitor ??
    (typeof window !== "undefined" && "Capacitor" in window)
  const embeddedShell = isEmbeddedAppShell({
    htmlClassName,
    userAgent,
    hasCapacitor,
  })
  const analyticsAllowed = input?.analyticsAllowed ?? isAnalyticsAllowed()
  return {
    phoneWeb,
    embeddedShell,
    analyticsAllowed,
    canSend: shouldSendMobileWebAppInstallAnalytics({
      phoneWeb,
      embeddedShell,
      analyticsAllowed,
    }),
  }
}

export function shouldFireGetAppBannerImpression(
  session: SessionStore | null,
  key = MOBILE_WEB_GET_APP_BANNER_IMPRESSION_SESSION_KEY
): boolean {
  if (!session) return true
  return session.getItem(key) == null
}

export function markGetAppBannerImpressionSent(
  session: SessionStore | null,
  key = MOBILE_WEB_GET_APP_BANNER_IMPRESSION_SESSION_KEY
): void {
  session?.setItem(key, "1")
}

export function openInAppClickProperties(input: {
  contentKind: MobileWebOpenInAppKind
  uiVariant: MobileWebOpenInAppUiVariant
}): Record<string, AllowedTrackValue> {
  return {
    content_kind: input.contentKind,
    ui_variant: input.uiVariant,
  }
}

export function appStoreClickProperties(input: {
  surface: MobileWebAppStorePromoSurface
}): Record<string, AllowedTrackValue> {
  return { surface: input.surface }
}

function defaultTrack(name: string, properties?: Record<string, AllowedTrackValue>) {
  if (typeof window === "undefined") return
  void import("@vercel/analytics")
    .then(({ track }) => track(name, properties))
    .catch(() => {})
}

function sendIfAllowed(
  ctx: ReturnType<typeof mobileWebAppInstallAnalyticsContext>,
  name: string,
  properties?: Record<string, AllowedTrackValue>,
  track: TrackFn = defaultTrack
) {
  if (!ctx.canSend) return
  track(name, properties)
}

/** Once per tab session while the banner is eligible and analytics are allowed. */
export function trackMobileWebGetAppBannerImpression(
  track: TrackFn = defaultTrack,
  session: SessionStore | null =
    typeof window !== "undefined" ? window.sessionStorage : null
): void {
  const ctx = mobileWebAppInstallAnalyticsContext()
  if (!ctx.canSend) return
  if (!shouldFireGetAppBannerImpression(session)) return
  markGetAppBannerImpressionSent(session)
  track(MOBILE_WEB_APP_INSTALL_EVENTS.getAppBannerImpression, {})
}

export function trackMobileWebGetAppBannerClick(
  track: TrackFn = defaultTrack
): void {
  sendIfAllowed(mobileWebAppInstallAnalyticsContext(), MOBILE_WEB_APP_INSTALL_EVENTS.getAppBannerClick, {}, track)
}

export function trackMobileWebGetAppBannerDismiss(
  track: TrackFn = defaultTrack
): void {
  sendIfAllowed(
    mobileWebAppInstallAnalyticsContext(),
    MOBILE_WEB_APP_INSTALL_EVENTS.getAppBannerDismiss,
    {},
    track
  )
}

export function trackMobileWebOpenInAppClick(input: {
  contentKind: MobileWebOpenInAppKind
  uiVariant: MobileWebOpenInAppUiVariant
  track?: TrackFn
}): void {
  sendIfAllowed(
    mobileWebAppInstallAnalyticsContext(),
    MOBILE_WEB_APP_INSTALL_EVENTS.openInAppClick,
    openInAppClickProperties(input),
    input.track ?? defaultTrack
  )
}

export function trackMobileWebAppStoreClick(input: {
  surface: MobileWebAppStorePromoSurface
  track?: TrackFn
}): void {
  sendIfAllowed(
    mobileWebAppInstallAnalyticsContext(),
    MOBILE_WEB_APP_INSTALL_EVENTS.appStoreClick,
    appStoreClickProperties(input),
    input.track ?? defaultTrack
  )
}
