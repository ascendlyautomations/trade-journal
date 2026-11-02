import {
  USER_FACING_ERROR_MESSAGES,
  toUserFacingErrorMessage,
} from "./userFacingError.ts"

/** Readable copy for phone-web load failures (no internal codes). */
export const MOBILE_WEB_FEED_LOAD_FAILED =
  "Couldn't load the feed. Check your connection and try again."

export const MOBILE_WEB_TRADES_LOAD_FAILED =
  "Couldn't load your trades. Check your connection and try again."

export const MOBILE_WEB_PROFILE_LOAD_FAILED =
  "Couldn't load this profile. Check your connection and try again."

export const MOBILE_WEB_OFFLINE_LABEL = "You're offline"

export function isBrowserOffline(): boolean {
  if (typeof navigator === "undefined") return false
  return navigator.onLine === false
}

/** Maps fetch/Supabase failures to user-safe text; prefers offline copy when applicable. */
export function mobileWebNetworkErrorMessage(
  error: unknown,
  fallback: string = USER_FACING_ERROR_MESSAGES.UNKNOWN_ERROR
): string {
  if (isBrowserOffline()) {
    return USER_FACING_ERROR_MESSAGES.CONNECTION_ERROR
  }
  return toUserFacingErrorMessage(error, fallback)
}

export function mobileWebTradesLoadErrorMessage(
  raw: string | null | undefined
): string | null {
  if (!raw?.trim()) return null
  if (isBrowserOffline()) {
    return USER_FACING_ERROR_MESSAGES.CONNECTION_ERROR
  }
  return toUserFacingErrorMessage(
    { message: raw },
    MOBILE_WEB_TRADES_LOAD_FAILED
  )
}
