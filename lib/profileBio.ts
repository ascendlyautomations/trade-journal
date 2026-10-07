/** Profile bio line limit shared by onboarding and Settings. */
export const PROFILE_BIO_MAX_LINES = 3

/** Keeps the first 3 lines. Extra newlines and pasted lines are dropped. */
export function constrainProfileBio(value: string): string {
  const normalized = value
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u2028/g, "\n")
    .replace(/\u2029/g, "\n")
  const lines = normalized.split("\n")
  if (lines.length <= PROFILE_BIO_MAX_LINES) return normalized
  return lines.slice(0, PROFILE_BIO_MAX_LINES).join("\n")
}
