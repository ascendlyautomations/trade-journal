import { NATIVE_IOS_URL_SCHEME } from "@/lib/nativeIosIdentity"

const UNIVERSAL_HOSTS = new Set(["www.tradetraxs.com", "tradetraxs.com"])

/** Paths that require an authenticated session on native. */
const PROTECTED_PREFIXES = [
  "/dashboard",
  "/explore",
  "/feed",
  "/leaderboard",
  "/messages",
  "/notifications",
  "/community",
  "/trade-rooms",
  "/profile/",
  "/trade/",
  "/analyst",
  "/onboarding",
] as const

export type ResolvedUniversalLink = {
  /** In-app path + query (starts with `/`). */
  path: string
  /** True when this URL is a supported Universal Link destination. */
  supported: boolean
  /** True when the destination normally requires auth. */
  requiresAuth: boolean
}

function isUniversalHost(hostname: string): boolean {
  return UNIVERSAL_HOSTS.has(hostname.toLowerCase())
}

/**
 * Map short share paths onto the app's canonical routes.
 * Additive only — existing `/feed?post=` and `/community?room=` keep working.
 */
export function canonicalizeUniversalPathname(
  pathname: string,
  search: string
): { path: string; supported: boolean } {
  const path = pathname.startsWith("/") ? pathname : `/${pathname}`
  const params = new URLSearchParams(
    search.startsWith("?") ? search.slice(1) : search
  )

  const postMatch = path.match(/^\/post\/([^/]+)\/?$/)
  if (postMatch) {
    params.set("post", decodeURIComponent(postMatch[1]))
    const q = params.toString()
    return { path: q ? `/feed?${q}` : "/feed", supported: true }
  }

  const reelMatch = path.match(/^\/reel\/([^/]+)\/?$/)
  if (reelMatch) {
    params.set("reel", decodeURIComponent(reelMatch[1]))
    const q = params.toString()
    return { path: q ? `/feed?${q}` : "/feed", supported: true }
  }

  const roomMatch = path.match(/^\/room\/([^/]+)\/?$/)
  if (roomMatch) {
    params.set("room", decodeURIComponent(roomMatch[1]))
    const q = params.toString()
    return { path: q ? `/community?${q}` : "/community", supported: true }
  }

  // Stories have no dedicated URL surface today — open the feed stories bar.
  if (/^\/story\/[^/]+\/?$/.test(path)) {
    return { path: "/feed", supported: true }
  }

  const tradeRooms = path === "/trade-rooms" || path.startsWith("/trade-rooms/")
  if (tradeRooms) {
    const rest = path.replace(/^\/trade-rooms/, "") || ""
    const q = params.toString()
    const dest = `/community${rest}`
    return { path: q ? `${dest}?${q}` : dest, supported: true }
  }

  const allow =
    path === "/" ||
    path === "/dashboard" ||
    path.startsWith("/dashboard/") ||
    path === "/explore" ||
    path.startsWith("/explore/") ||
    path === "/feed" ||
    path.startsWith("/feed/") ||
    path === "/leaderboard" ||
    path.startsWith("/leaderboard/") ||
    path === "/messages" ||
    path.startsWith("/messages/") ||
    path === "/notifications" ||
    path.startsWith("/notifications/") ||
    path === "/community" ||
    path.startsWith("/community/") ||
    path.startsWith("/profile/") ||
    path.startsWith("/trade/") ||
    path === "/analyst" ||
    path.startsWith("/analyst/") ||
    path === "/onboarding" ||
    path.startsWith("/onboarding/") ||
    path.startsWith("/login")

  if (!allow) {
    const q = params.toString()
    return { path: q ? `${path}?${q}` : path, supported: false }
  }

  const q = params.toString()
  return { path: q ? `${path}?${q}` : path, supported: true }
}

export function pathRequiresAuth(pathWithQuery: string): boolean {
  const pathOnly = pathWithQuery.split("?")[0] || "/"
  if (pathOnly === "/login" || pathOnly.startsWith("/login/")) return false
  if (pathOnly === "/") return false
  return PROTECTED_PREFIXES.some(
    (prefix) => pathOnly === prefix || pathOnly.startsWith(prefix)
  )
}

/**
 * Resolve an absolute URL (Universal Link or in-app) to a navigable app path.
 * Returns null for non-TradeTraxs / OAuth custom-scheme URLs.
 */
export function resolveUniversalLinkPath(
  rawUrl: string
): ResolvedUniversalLink | null {
  const trimmed = rawUrl.trim()
  if (!trimmed) return null

  // OAuth custom scheme is handled by the native Swift app / OAuth helpers.
  if (trimmed.startsWith(`${NATIVE_IOS_URL_SCHEME}://`)) return null

  let url: URL
  try {
    url = new URL(trimmed)
  } catch {
    return null
  }

  if (url.protocol !== "https:" && url.protocol !== "http:") return null
  if (!isUniversalHost(url.hostname)) return null

  const { path, supported } = canonicalizeUniversalPathname(
    url.pathname || "/",
    url.search || ""
  )

  return {
    path,
    supported,
    requiresAuth: pathRequiresAuth(path),
  }
}

/** Build `/login?next=` for a protected destination. */
export function loginPathWithNext(destination: string): string {
  const next = destination.startsWith("/") ? destination : `/${destination}`
  return `/login?next=${encodeURIComponent(next)}`
}
