import type { User } from "@supabase/supabase-js"

export type PasswordManagementMode = "change" | "create"

/**
 * Password UI source of truth (Settings):
 * - Traditional email/password accounts: not a Google auth user → inline Change password.
 * - Google accounts: profiles.has_email_password (persisted in DB, loaded via UserProfileProvider).
 *
 * Supabase identities / app_metadata.providers were unreliable after updateUser({ password })
 * and local React state did not survive logout.
 */

function listAuthProviders(user: User): string[] {
  const fromMetadata = user.app_metadata?.providers
  if (Array.isArray(fromMetadata)) {
    return fromMetadata.filter((p): p is string => typeof p === "string")
  }

  const primary = user.app_metadata?.provider
  if (typeof primary === "string" && primary.trim()) {
    return [primary.trim()]
  }

  return (
    user.identities
      ?.map((identity) => identity.provider)
      .filter((p): p is string => typeof p === "string") ?? []
  )
}

export function isGoogleAuthUser(user: User | null | undefined): boolean {
  if (!user) return false
  return listAuthProviders(user).includes("google")
}

/** Legacy — not used for Google Settings UI; prefer profiles.has_email_password. */
export function userHasEmailPasswordIdentity(
  user: User | null | undefined
): boolean {
  if (!user) return false

  if (listAuthProviders(user).includes("email")) return true

  return user.identities?.some((identity) => identity.provider === "email") ?? false
}

export function profileHasEmailPasswordFlag(
  hasEmailPassword: boolean | null | undefined
): boolean {
  return hasEmailPassword === true
}

export function resolveGooglePasswordUiMode(
  profileHasEmailPassword: boolean | null | undefined
): "create" | "update" {
  return profileHasEmailPasswordFlag(profileHasEmailPassword)
    ? "update"
    : "create"
}
