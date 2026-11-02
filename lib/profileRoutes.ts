import { normalizeProfileUsername } from "./profileUsername.ts"

const UUID_SEGMENT_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function isProfileUuidSegment(segment: string): boolean {
  return UUID_SEGMENT_RE.test(segment.trim())
}

export function buildProfilePath(username: string): string {
  const normalized = normalizeProfileUsername(username)
  return normalized ? `/profile/${normalized}` : "/profile"
}

export function profilePath(profile: {
  username?: string | null
  id?: string | null
}): string {
  const normalized = normalizeProfileUsername(profile.username ?? "")
  if (normalized) return buildProfilePath(normalized)
  const id = profile.id != null ? String(profile.id).trim() : ""
  return id ? `/profile/${id}` : "/profile"
}

/** Signed-in Profile tab destination. Never returns an empty `/profile` when a user id exists. */
export function signedInProfileHref(
  profile: { username?: string | null; id?: string | null } | null | undefined,
  userId?: string | null
): string {
  if (profile) return profilePath(profile)
  if (userId) return profilePath({ id: userId })
  return "/profile"
}
