import { NATIVE_IOS_URL_SCHEME } from "@/lib/nativeIosIdentity"
import { SITE_URL } from "@/lib/site"

/**
 * Must match Info.plist CFBundleURLSchemes, Capacitor appId / Xcode bundle ID,
 * and Supabase Auth redirect allow-list (Google today; Apple later).
 */
export const NATIVE_IOS_OAUTH_SCHEME = NATIVE_IOS_URL_SCHEME

/** Custom-scheme deep link that Capacitor receives via `appUrlOpen`. */
export const NATIVE_IOS_OAUTH_CALLBACK =
  `${NATIVE_IOS_OAUTH_SCHEME}://auth/callback` as const

/**
 * Production HTTPS bridge used as Supabase `redirectTo` for Capacitor iOS only.
 * Never use LAN / localhost — Cap may load a local WebView for development, but
 * OAuth must always return through the deployed production bridge.
 *
 * Allow-list in Supabase (and Google / future Apple providers):
 * - https://www.tradetraxs.com/api/auth/native-callback
 * - com.tradetraxs.ios://auth/callback
 */
export const NATIVE_IOS_OAUTH_HTTPS_BRIDGE =
  `${SITE_URL}/api/auth/native-callback` as const
