import { DEMO_USER_ID } from "./demo/constants"
import { normalizeProfileUsername } from "./profileUsername"

/** Demo fixture usernames — client-side demo only; exclude if present in production DB. */
const DEMO_USERNAMES = new Set([
  "john_trades",
  "alex_futures",
  "jordan_scalps",
  "sarah_indices",
  "mike_swings",
  "eli_prop",
])

const RESERVED_USERNAMES = new Set(["test", "demo", "admin"])

export function isExcludedPublicUsername(
  username: string | null | undefined
): boolean {
  const normalized = normalizeProfileUsername(username ?? "")
  if (!normalized) return true
  if (DEMO_USERNAMES.has(normalized)) return true
  if (RESERVED_USERNAMES.has(normalized)) return true
  if (normalized.startsWith("e2e-")) return true
  if (normalized.includes("-test-")) return true
  if (normalized.endsWith("-test")) return true
  return false
}

export function isExcludedPublicUserId(
  userId: string | null | undefined
): boolean {
  return userId != null && userId.trim() === DEMO_USER_ID
}
