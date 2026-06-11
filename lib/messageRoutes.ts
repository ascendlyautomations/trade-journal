import { isProfileUuidSegment } from "./profileRoutes"
import { normalizeProfileUsername } from "./profileUsername"

export function isConversationUuidSegment(segment: string): boolean {
  return isProfileUuidSegment(segment)
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
