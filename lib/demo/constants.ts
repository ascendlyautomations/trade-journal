/** Stable synthetic user id for demo cache and UI — never written to Supabase. */
export const DEMO_USER_ID = "00000000-0000-4000-8000-00000000demo"

export const DEMO_PROFILE_PATH = "/profile/john_trades"

export function isDemoUserId(userId: string | null | undefined): boolean {
  return userId != null && userId.trim() === DEMO_USER_ID
}
