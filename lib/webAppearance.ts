import {
  AUTH_ROUTE_PREFIXES,
  MARKETING_EXACT_PATHS,
  ONBOARDING_ROUTE_PREFIXES,
  PRE_CHECKOUT_ROUTE_PREFIXES,
  PUBLIC_LEGAL_EXACT_PATHS,
  isMarketingRoute,
  isPublicLegalRoute,
  isStandaloneFlowRoute,
} from "@/lib/authRoutes"

/** Authenticated web appearance. Independent of html[data-theme]. */
export const WEB_APPEARANCES = ["dark", "light", "og"] as const

export type WebAppearance = (typeof WEB_APPEARANCES)[number]

export const DEFAULT_WEB_APPEARANCE: WebAppearance = "dark"

export const WEB_APPEARANCE_STORAGE_KEY = "tt-web-appearance"

export const WEB_APPEARANCE_CHANGE_EVENT = "tt-appearance-change"

const PUBLIC_THEME_COLOR = "#0b1f3a"

const APPEARANCE_THEME_COLOR: Record<WebAppearance, string> = {
  dark: "#0d1117",
  light: "#f6f8fa",
  og: "#0b1f3a",
}

/** Paths that must never receive the authenticated appearance attribute. */
const APPEARANCE_OPT_OUT_EXACT = [
  ...MARKETING_EXACT_PATHS,
  ...PUBLIC_LEGAL_EXACT_PATHS,
  "/copyright",
] as const

const APPEARANCE_OPT_OUT_PREFIXES = [
  ...AUTH_ROUTE_PREFIXES,
  ...ONBOARDING_ROUTE_PREFIXES,
  ...PRE_CHECKOUT_ROUTE_PREFIXES,
  "/demo",
  "/marketing",
  "/native",
] as const

export function parseWebAppearance(value: string | null | undefined): WebAppearance {
  if (value === "light" || value === "og" || value === "dark") return value
  return DEFAULT_WEB_APPEARANCE
}

export function shouldApplyWebAppearance(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  if (pathname === "/copyright") return false
  if (isStandaloneFlowRoute(pathname)) return false
  if (isMarketingRoute(pathname)) return false
  if (isPublicLegalRoute(pathname)) return false
  if (pathname === "/demo" || pathname.startsWith("/demo/")) return false
  if (pathname === "/marketing" || pathname.startsWith("/marketing/")) return false
  if (pathname === "/native" || pathname.startsWith("/native/")) return false
  return true
}

/** null removes the attribute (public, auth, onboarding, native). */
export function appearanceForPath(
  pathname: string | null | undefined,
  stored: string | null | undefined,
  options?: { native?: boolean },
): WebAppearance | null {
  if (options?.native) return null
  if (!shouldApplyWebAppearance(pathname)) return null
  return parseWebAppearance(stored)
}

export function readWebAppearance(): WebAppearance {
  if (typeof window === "undefined") return DEFAULT_WEB_APPEARANCE
  try {
    return parseWebAppearance(window.localStorage.getItem(WEB_APPEARANCE_STORAGE_KEY))
  } catch {
    return DEFAULT_WEB_APPEARANCE
  }
}

function themeColorFor(appearance: WebAppearance | null): string {
  if (!appearance) return PUBLIC_THEME_COLOR
  return APPEARANCE_THEME_COLOR[appearance]
}

function syncThemeColor(appearance: WebAppearance | null) {
  if (typeof document === "undefined") return
  const meta = document.querySelector('meta[name="theme-color"]')
  if (!meta) return
  meta.setAttribute("content", themeColorFor(appearance))
}

export function applyWebAppearanceForPath(pathname: string | null | undefined) {
  if (typeof document === "undefined") return
  const root = document.documentElement
  const native =
    root.classList.contains("tt-native") || root.classList.contains("tt-native-ios")
  if (native) {
    root.removeAttribute("data-tt-appearance")
    syncThemeColor(null)
    return
  }
  // A missing pathname must not wipe the pre-paint attribute. The boot
  // script already applied the correct value from location.pathname.
  if (!pathname) return
  const next = appearanceForPath(pathname, readWebAppearance())
  if (next == null) root.removeAttribute("data-tt-appearance")
  else root.setAttribute("data-tt-appearance", next)
  syncThemeColor(next)
}

export function writeWebAppearance(value: WebAppearance) {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(WEB_APPEARANCE_STORAGE_KEY, value)
  } catch {
    /* preference still applies for this view */
  }
  applyWebAppearanceForPath(window.location.pathname)
  window.dispatchEvent(new Event(WEB_APPEARANCE_CHANGE_EVENT))
}

/**
 * Blocking boot script. Runs before the authenticated shell paints.
 * Default is dark. Public, auth, onboarding, and native shells are left alone.
 */
export function webAppearanceBootScript(): string {
  const exact = JSON.stringify(APPEARANCE_OPT_OUT_EXACT)
  const prefixes = JSON.stringify(APPEARANCE_OPT_OUT_PREFIXES)
  const key = JSON.stringify(WEB_APPEARANCE_STORAGE_KEY)
  return `(function(){try{var root=document.documentElement;if(root.classList.contains("tt-native")||root.classList.contains("tt-native-ios"))return;var path=location.pathname||"/";var exact=${exact};var prefixes=${prefixes};function optedOut(p){if(exact.indexOf(p)!==-1)return true;for(var i=0;i<prefixes.length;i++){var pre=prefixes[i];if(p===pre||p.indexOf(pre+"/")===0)return true;}return false;}var meta=document.querySelector('meta[name="theme-color"]');if(optedOut(path)){root.removeAttribute("data-tt-appearance");if(meta)meta.setAttribute("content","${PUBLIC_THEME_COLOR}");return;}var raw=null;try{raw=localStorage.getItem(${key});}catch(e){}var next=raw==="light"||raw==="og"||raw==="dark"?raw:"dark";root.setAttribute("data-tt-appearance",next);if(meta)meta.setAttribute("content",next==="light"?"${APPEARANCE_THEME_COLOR.light}":next==="og"?"${APPEARANCE_THEME_COLOR.og}":"${APPEARANCE_THEME_COLOR.dark}");}catch(e){}})();`
}
