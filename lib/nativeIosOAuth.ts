import { isNativeIos } from "@/lib/nativePlatform"
import { supabase } from "@/lib/supabaseClient"
import {
  NATIVE_IOS_OAUTH_HTTPS_BRIDGE,
  NATIVE_IOS_OAUTH_SCHEME,
} from "@/lib/nativeIosOAuthUrls"

export {
  NATIVE_IOS_OAUTH_CALLBACK,
  NATIVE_IOS_OAUTH_HTTPS_BRIDGE,
  NATIVE_IOS_OAUTH_SCHEME,
} from "@/lib/nativeIosOAuthUrls"

/**
 * Always returns the production HTTPS bridge.
 * OAuth redirectTo must never be localhost / 127.0.0.1 / 192.168.x.x.
 */
export function buildNativeIosOAuthRedirectTo(): string {
  return NATIVE_IOS_OAUTH_HTTPS_BRIDGE
}

const NEXT_PATH_KEY = "tt_native_ios_oauth_next_v1"
export const NATIVE_IOS_OAUTH_FLOW_ACTIVE_KEY = "tt_native_ios_oauth_active_v1"

function isSafeAppPath(path: string): boolean {
  return path.startsWith("/") && !path.startsWith("//")
}

export function stashNativeIosOAuthNextPath(path: string) {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(
      NEXT_PATH_KEY,
      isSafeAppPath(path) ? path : "/dashboard"
    )
    sessionStorage.setItem(NATIVE_IOS_OAUTH_FLOW_ACTIVE_KEY, "1")
  } catch {
    /* ignore */
  }
}

export function takeNativeIosOAuthNextPath(): string {
  if (typeof window === "undefined") return "/dashboard"
  try {
    const next = sessionStorage.getItem(NEXT_PATH_KEY)
    sessionStorage.removeItem(NEXT_PATH_KEY)
    sessionStorage.removeItem(NATIVE_IOS_OAUTH_FLOW_ACTIVE_KEY)
    if (next && isSafeAppPath(next)) return next
  } catch {
    /* ignore */
  }
  return "/dashboard"
}

export function clearNativeIosOAuthStash() {
  if (typeof window === "undefined") return
  try {
    sessionStorage.removeItem(NEXT_PATH_KEY)
    sessionStorage.removeItem(NATIVE_IOS_OAUTH_FLOW_ACTIVE_KEY)
  } catch {
    /* ignore */
  }
}

function parseCallbackUrl(url: string): URL | null {
  try {
    return new URL(url)
  } catch {
    try {
      const normalized = url.replace(
        new RegExp(`^${NATIVE_IOS_OAUTH_SCHEME}:\\/\\/`, "i"),
        "https://oauth.callback/"
      )
      return new URL(normalized)
    } catch {
      return null
    }
  }
}

function isNativeOAuthCallbackUrl(url: string): boolean {
  return new RegExp(`^${NATIVE_IOS_OAUTH_SCHEME}:\\/\\/`, "i").test(url.trim())
}

async function closeAuthBrowser() {
  // Capacitor Browser plugin removed — nothing to close.
}

/**
 * Start Google OAuth for legacy native-shell markers (cookie/UA).
 * Capacitor Browser removed — navigates the current window to the OAuth URL.
 * The Swift app owns production OAuth via ASWebAuthenticationSession.
 */
export async function startNativeIosGoogleOAuth(nextPath: string): Promise<void> {
  if (!isNativeIos()) {
    throw new Error("startNativeIosGoogleOAuth is native iOS shell only")
  }

  stashNativeIosOAuthNextPath(nextPath)

  const redirectTo = buildNativeIosOAuthRedirectTo()

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: {
      redirectTo,
      skipBrowserRedirect: true,
    },
  })

  if (error) {
    clearNativeIosOAuthStash()
    throw error
  }
  if (!data.url) {
    clearNativeIosOAuthStash()
    throw new Error("No OAuth URL returned")
  }

  window.location.assign(data.url)
}

/**
 * Handle `tradetraxs://…` deep link after Google → Supabase → HTTPS bridge.
 * Returns the in-app path to navigate to, or null if the URL is not an OAuth callback.
 */
export async function completeNativeIosOAuthFromUrl(
  url: string
): Promise<string | null> {
  if (!isNativeIos()) return null
  if (!isNativeOAuthCallbackUrl(url)) return null

  const parsed = parseCallbackUrl(url)
  if (!parsed) return null

  const errorDescription =
    parsed.searchParams.get("error_description") ||
    parsed.searchParams.get("error")
  if (errorDescription) {
    clearNativeIosOAuthStash()
    await closeAuthBrowser()
    throw new Error(errorDescription)
  }

  const code = parsed.searchParams.get("code")
  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (error) {
      clearNativeIosOAuthStash()
      await closeAuthBrowser()
      throw error
    }
  } else {
    // Legacy implicit fragments (access_token / refresh_token).
    const hash = parsed.hash?.startsWith("#")
      ? parsed.hash.slice(1)
      : parsed.hash || ""
    const hashParams = new URLSearchParams(hash)
    const access_token = hashParams.get("access_token")
    const refresh_token = hashParams.get("refresh_token")
    if (access_token && refresh_token) {
      const { error } = await supabase.auth.setSession({
        access_token,
        refresh_token,
      })
      if (error) {
        clearNativeIosOAuthStash()
        await closeAuthBrowser()
        throw error
      }
    } else {
      return null
    }
  }

  await closeAuthBrowser()
  return takeNativeIosOAuthNextPath()
}
