export const BETA_ROOM_SLUG = "tradetraxs-beta"
export const BETA_ANNOUNCEMENTS_SECTION = "announcements"

const TEST_DISCOVERY_ROOM_NAMES = new Set([
  "cache hit room",
  "scroll verify room",
  "scroll room",
])

/** Rooms hidden from public discovery / recommendation surfaces (beta hub retains direct access). */
export function isExcludedDiscoveryRoomSlug(
  slug: string | null | undefined
): boolean {
  return String(slug ?? "").trim().toLowerCase() === BETA_ROOM_SLUG
}

/** E2E / dev fixture rooms that should not appear in user-facing discovery. */
export function isExcludedTestDiscoveryRoom(room: {
  name?: string | null
  slug?: string | null
}): boolean {
  const name = String(room.name ?? "").trim().toLowerCase()
  if (TEST_DISCOVERY_ROOM_NAMES.has(name)) return true

  const slug = String(room.slug ?? "").trim().toLowerCase()
  if (!slug) return false

  if (slug.startsWith("scroll-cache-")) return true
  if (slug.startsWith("scroll-verify-")) return true
  if (slug.startsWith("e2e-")) return true
  if (slug.includes("-test-")) return true

  return false
}

export function isPublicDiscoveryRoom(room: {
  slug?: string | null
  name?: string | null
  show_on_profile?: boolean | null
  is_private?: boolean | null
}): boolean {
  if (isExcludedDiscoveryRoomSlug(room.slug)) return false
  if (isExcludedTestDiscoveryRoom(room)) return false
  if (room.is_private === true) return false
  return room.show_on_profile !== false
}

export function isBetaAnnouncementsSection(
  roomSlug: string | null | undefined,
  section: { name?: string | null; allow_members_chat?: boolean } | null | undefined
): boolean {
  return (
    String(roomSlug ?? "").trim().toLowerCase() === BETA_ROOM_SLUG &&
    String(section?.name ?? "").trim().toLowerCase() === BETA_ANNOUNCEMENTS_SECTION &&
    section?.allow_members_chat === false
  )
}
