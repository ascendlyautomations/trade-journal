/** Profiles that may appear on discovery surfaces (explore, search, social lists). */
export function isPublicDiscoverableProfile(
  profile: { is_private?: boolean | null } | null | undefined
): boolean {
  return profile != null
}

