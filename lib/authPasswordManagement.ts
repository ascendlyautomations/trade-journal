import type { User } from "@supabase/supabase-js"

export type PasswordManagementMode = "change" | "create"

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

export function userHasEmailPasswordIdentity(
  user: User | null | undefined
): boolean {
  if (!user) return false

  if (listAuthProviders(user).includes("email")) return true

  return user.identities?.some((identity) => identity.provider === "email") ?? false
}

/** Google-only users set a password via email link; everyone else uses inline change. */
export function getPasswordManagementMode(
  user: User | null | undefined
): PasswordManagementMode {
  if (!user) return "change"
  if (isGoogleAuthUser(user) && !userHasEmailPasswordIdentity(user)) {
    return "create"
  }
  return "change"
}
