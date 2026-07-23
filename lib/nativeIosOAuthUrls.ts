import { SITE_URL } from "@/lib/site"

/** Must match Info.plist CFBundleURLSchemes and Supabase Auth redirect allow-list. */
export const NATIVE_IOS_OAUTH_SCHEME = "com.tradetraxs.app"

/** Custom-scheme deep link that Capacitor receives via `appUrlOpen`. */
export const NATIVE_IOS_OAUTH_CALLBACK =
  `${NATIVE_IOS_OAUTH_SCHEME}://auth/callback` as const

/**
 * Production HTTPS bridge used as Supabase `redirectTo` for Capacitor iOS only.
 * Never use LAN / localhost — Cap may load a local WebView for development, but
 * OAuth must always return through the deployed production bridge.
 */
export const NATIVE_IOS_OAUTH_HTTPS_BRIDGE =
  `${SITE_URL}/api/auth/native-callback` as const
