import { SITE_URL } from "./site.ts"

/**
 * Phone-web "Open in App" links.
 *
 * Native contract (read-only, not modified here):
 * `DeepLinkParser` in native-ios/.../DeepLinkParsing.swift and
 * `APPLE_APP_SITE_ASSOCIATION_PATHS` for applinks:www.tradetraxs.com
 * and applinks:tradetraxs.com.
 *
 * Content destinations this helper will emit:
 * - public profile → https://www.tradetraxs.com/profile/{id-or-username}
 * - trade → /trade/{id} or /feed?trade={id}
 * - post → /post/{id} or /feed?post={id}
 * - clip → /reel/{id} or /feed?reel={id}
 *
 * There is no /clips universal-link path. Clips use the existing /reel
 * contract. Custom URL schemes are not used. Nothing here redirects;
 * the anchor is only followed when the visitor taps it.
 * If the app is not installed, the https link stays on the website.
 *
 * App Store fallback is separate and only exists when
 * NEXT_PUBLIC_IOS_APP_STORE_URL is an https apps.apple.com listing.
 * Achievement pages are a native `/feed?achievement=` destination and
 * are not given this action.
 */

export const MOBILE_WEB_UNIVERSAL_LINK_ORIGIN = SITE_URL

export type MobileWebOpenInAppKind = "profile" | "trade" | "post" | "clip"

export type MobileWebOpenInAppLink = {
  kind: MobileWebOpenInAppKind
  href: string
}

function contentSegment(raw: string): string | null {
  let value = raw.trim()
  if (!value) return null
  try {
    value = decodeURIComponent(value)
  } catch {
    return null
  }
  value = value.trim()
  if (!value || value === "." || value === "..") return null
  if (/[/?#\\\s]/.test(value)) return null
  return encodeURIComponent(value)
}

function link(
  kind: MobileWebOpenInAppKind,
  path: string
): MobileWebOpenInAppLink {
  return { kind, href: `${MOBILE_WEB_UNIVERSAL_LINK_ORIGIN}${path}` }
}

/** Canonical content URL for a known id. Matches the native parser paths. */
export function mobileWebOpenInAppContentLink(
  kind: MobileWebOpenInAppKind,
  id: string
): MobileWebOpenInAppLink | null {
  const segment = contentSegment(id)
  if (!segment) return null
  switch (kind) {
    case "profile":
      return link(kind, `/profile/${segment}`)
    case "trade":
      return link(kind, `/trade/${segment}`)
    case "post":
      return link(kind, `/post/${segment}`)
    case "clip":
      return link(kind, `/reel/${segment}`)
    default:
      return null
  }
}

/**
 * Universal link for the current website location.
 * Returns null for routes the native parser does not open as this content.
 */
export function mobileWebOpenInAppLink(
  pathname: string,
  search = ""
): MobileWebOpenInAppLink | null {
  const path = pathname.startsWith("/") ? pathname : `/${pathname}`
  const params = new URLSearchParams(
    search.startsWith("?") ? search.slice(1) : search
  )

  const profile = path.match(/^\/profile\/([^/]+)\/?$/)
  if (profile) {
    const segment = contentSegment(profile[1])
    return segment ? link("profile", `/profile/${segment}`) : null
  }

  const trade = path.match(/^\/trade\/([^/]+)\/?$/)
  if (trade) {
    const segment = contentSegment(trade[1])
    return segment ? link("trade", `/trade/${segment}`) : null
  }

  const post = path.match(/^\/post\/([^/]+)\/?$/)
  if (post) {
    const segment = contentSegment(post[1])
    return segment ? link("post", `/post/${segment}`) : null
  }

  const reel = path.match(/^\/reel\/([^/]+)\/?$/)
  if (reel) {
    const segment = contentSegment(reel[1])
    return segment ? link("clip", `/reel/${segment}`) : null
  }

  if (path === "/feed" || path === "/feed/") {
    // Same precedence as DeepLinkParser.parseFeed: trade, then reel, then post.
    const tradeId = params.get("trade")
    if (tradeId) {
      const segment = contentSegment(tradeId)
      return segment ? link("trade", `/feed?trade=${segment}`) : null
    }
    const reelId = params.get("reel")
    if (reelId) {
      const segment = contentSegment(reelId)
      return segment ? link("clip", `/feed?reel=${segment}`) : null
    }
    const postId = params.get("post")
    if (postId) {
      const segment = contentSegment(postId)
      return segment ? link("post", `/feed?post=${segment}`) : null
    }
  }

  return null
}
