import { isProfileUuidSegment } from "./profileRoutes"
import { normalizeProfileUsername } from "./profileUsername"

export function isConversationUuidSegment(segment: string): boolean {
  return isProfileUuidSegment(segment)
}

/** True for `/messages/:id` threads — not the inbox `/messages`. */
export function isDmConversationPath(
  pathname: string | null | undefined
): boolean {
  if (!pathname) return false
  const match = pathname.match(/^\/messages\/([^/]+)\/?$/)
  if (!match) return false
  const segment = match[1]?.trim()
  return Boolean(segment)
}

export function buildDmThreadPath(username: string): string {
  const normalized = normalizeProfileUsername(username)
  return normalized ? `/messages/${normalized}` : "/messages"
}

export function dmThreadPath(user: {
  username?: string | null
  id?: string | null
}): string {
  const normalized = normalizeProfileUsername(user.username ?? "")
  if (normalized) return buildDmThreadPath(normalized)
  const id = user.id != null ? String(user.id).trim() : ""
  return id ? `/messages/${id}` : "/messages"
}

export function groupThreadPath(conversationId: string): string {
  const id = conversationId.trim()
  return id ? `/messages/${id}` : "/messages"
}
