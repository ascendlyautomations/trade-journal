import type { SupabaseClient } from "@supabase/supabase-js"
import { persistSettingsProfileEverywhere } from "@/lib/settingsProfileSync"
import type { UserProfileSlice } from "@/lib/UserProfileProvider"
import { writeUserBootstrapProfile } from "@/lib/userBootstrapCache"

export function readProfileHasEmailPassword(
  profile: UserProfileSlice | Record<string, unknown> | null | undefined
): boolean {
  if (!profile || typeof profile !== "object") return false
  return (profile as Record<string, unknown>).has_email_password === true
}

/** Persist that this account can sign in with email + password (survives logout). */
export async function markProfileHasEmailPassword(
  client: SupabaseClient,
  userId: string
): Promise<{ ok: true } | { ok: false; message: string }> {
  const id = userId.trim()
  if (!id) {
    return { ok: false, message: "Missing user id." }
  }

  const { error } = await client
    .from("profiles")
    .update({ has_email_password: true })
    .eq("id", id)

  if (error) {
    console.error("markProfileHasEmailPassword:", error.message)
    return {
      ok: false,
      message: "Could not save password status. Please try again.",
    }
  }

  return { ok: true }
}

export function applyHasEmailPasswordToCaches(
  userId: string,
  shared: UserProfileSlice | null,
  settingsRow: Record<string, unknown> | null
): {
  shared: UserProfileSlice | null
  settingsRow: Record<string, unknown> | null
} {
  const nextShared = shared ? { ...shared, has_email_password: true } : null
  const nextSettings = settingsRow
    ? { ...settingsRow, has_email_password: true }
    : shared
      ? ({ ...shared, has_email_password: true } as Record<string, unknown>)
      : null

  if (nextSettings) {
    persistSettingsProfileEverywhere(userId, nextSettings)
  } else if (nextShared) {
    writeUserBootstrapProfile(userId, nextShared)
  }

  return { shared: nextShared, settingsRow: nextSettings }
}
