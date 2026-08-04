/** Desktop Profile Trades list pagination (unchanged). */
export const PROFILE_TRADES_PAGE_SIZE_DESKTOP = 5

/** Mobile Profile Trades grid / list pagination. */
export const PROFILE_TRADES_PAGE_SIZE_MOBILE = 12

const MAX_MD_QUERY = "(max-width: 767px)"

/** Resolve page size at fetch time so mobile gets 12 without changing desktop. */
export function resolveProfileTradesPageSize(): number {
  if (typeof window === "undefined") return PROFILE_TRADES_PAGE_SIZE_DESKTOP
  return window.matchMedia(MAX_MD_QUERY).matches
    ? PROFILE_TRADES_PAGE_SIZE_MOBILE
    : PROFILE_TRADES_PAGE_SIZE_DESKTOP
}
