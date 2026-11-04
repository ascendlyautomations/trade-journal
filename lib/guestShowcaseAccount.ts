/** Production showcase auth user (`tradetraxsdemo@gmail.com`) — keep in sync with guest-session edge function. */
export const SHOWCASE_USER_ID = "3daf15b8-2f5d-48c8-ac98-75bca6c878f4"

/** Explore-as-guest / marketing previews — production showcase profile fields. */
export const SHOWCASE_USERNAME = "tradetraxs_demo" as const

/** Public storage URL for the showcase avatar (same as live Explore guest profile). */
export const SHOWCASE_AVATAR_URL =
  "https://fobudrkniacatvilbofw.supabase.co/storage/v1/object/public/avatars/3daf15b8-2f5d-48c8-ac98-75bca6c878f4/opt/1791168141251.jpg" as const

export function isShowcaseUserId(userId: string | null | undefined): boolean {
  return userId != null && userId.trim().toLowerCase() === SHOWCASE_USER_ID
}

export function showcaseProfilePath(): string {
  return `/profile/${SHOWCASE_USER_ID}`
}
