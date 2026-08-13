import { NATIVE_IOS_URL_SCHEME } from "@/lib/nativeIosIdentity"
import { SITE_URL } from "@/lib/site"

/**
 * Must match native Info.plist CFBundleURLSchemes (`tradetraxs`) and the
 * Supabase Auth redirect allow-list (Google today; Apple later).
 */
export const NATIVE_IOS_OAUTH_SCHEME = NATIVE_IOS_URL_SCHEME

/** Custom-scheme deep link the native app receives after the HTTPS bridge. */
export const NATIVE_IOS_OAUTH_CALLBACK =
  `${NATIVE_IOS_OAUTH_SCHEME}://auth/callback` as const

/**
 * Production HTTPS bridge used as Supabase `redirectTo` for native iOS.
 * Never use LAN / localhost — OAuth must always return through the deployed bridge.
 *
 * Allow-list in Supabase (and Google / future Apple providers):
 * - https://www.tradetraxs.com/api/auth/native-callback
 * - tradetraxs://auth/callback
 */
export const NATIVE_IOS_OAUTH_HTTPS_BRIDGE =
  `${SITE_URL}/api/auth/native-callback` as const
