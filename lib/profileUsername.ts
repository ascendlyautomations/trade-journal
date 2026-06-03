export const USERNAME_FORMAT_HINT =
  "Only lowercase letters, numbers, and underscores allowed"

const INVALID_USERNAME_CHARS = /[^a-z0-9_]/g

/** While typing: lowercase and strip invalid characters (no trim). */
export function sanitizeUsernameInputForTyping(value: string): string {
  return value.toLowerCase().replace(INVALID_USERNAME_CHARS, "")
}

/** On save: lowercase, trim, strip invalid characters. */
export function normalizeProfileUsername(value: string): string {
  return value.toLowerCase().trim().replace(INVALID_USERNAME_CHARS, "")
}

/** Returns an error message if username is empty after normalization. */
export function validateProfileUsernameNotEmpty(value: string): string | null {
  if (!normalizeProfileUsername(value).length) {
    return "Please choose a username."
  }
  return null
}

/** Postgres duplicate key — narrow to profiles.username unique constraint when possible */
export function isProfilesUsernameConflict(err: {
  code?: string
  message?: string
  details?: string | null
}): boolean {
  if (err.code !== "23505") return false
  const s = `${err.message ?? ""} ${err.details ?? ""}`.toLowerCase()
  return s.includes("username")
}
