import { showcaseProfilePath } from "@/lib/guestShowcaseAccount"

/** Stable synthetic user id for demo cache and UI — never written to Supabase. */
export const DEMO_USER_ID = "00000000-0000-4000-8000-00000000demo"

/** Bundled local demo profile (legacy sessionStorage demo mode only). */
export const DEMO_PROFILE_PATH = "/profile/john_trades"

/** Live showcase profile path (Explore as Guest / tradetraxsdemo@gmail.com). */
export const SHOWCASE_PROFILE_PATH = showcaseProfilePath()

export function isDemoUserId(userId: string | null | undefined): boolean {
  return userId != null && userId.trim() === DEMO_USER_ID
}
