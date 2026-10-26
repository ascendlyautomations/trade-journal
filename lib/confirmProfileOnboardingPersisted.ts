import type { SupabaseClient } from "@supabase/supabase-js"
import { toUserFacingErrorMessage as handleSupabaseError } from "./userFacingError.ts"

export type ConfirmProfileOnboardingResult =
  | { ok: true; profile: { id: string; username: string | null } }
  | { ok: false; message: string }

/**
 * After profiles UPDATE, confirm exactly one row persisted with onboarding_completed.
 * Prevents false-success when RLS blocks the write or the profile row is missing.
 */
export async function confirmProfileOnboardingPersisted(
  supabase: SupabaseClient,
  userId: string,
  expectedUsername: string
): Promise<ConfirmProfileOnboardingResult> {
  const { data, error } = await supabase
    .from("profiles")
    .select("id, username, onboarding_completed")
    .eq("id", userId)
    .maybeSingle()

  if (error) {
    return { ok: false, message: handleSupabaseError(error) }
  }
  if (!data) {
    return {
      ok: false,
      message: "Profile not found. Sign out and sign in again, then retry.",
    }
  }
  if (data.onboarding_completed !== true) {
    return {
      ok: false,
      message: "Could not save onboarding. Check your connection and try again.",
    }
  }
  const savedUsername = String(data.username ?? "").trim()
  const expected = expectedUsername.trim()
  if (savedUsername !== expected) {
    return {
      ok: false,
      message: "Profile update did not apply. Try again.",
    }
  }
  return { ok: true, profile: { id: data.id, username: data.username } }
}
