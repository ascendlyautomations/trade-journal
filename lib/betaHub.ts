export const BETA_ROOM_SLUG = "tradetraxs-beta"
export const BETA_ANNOUNCEMENTS_SECTION = "announcements"

/** Rooms hidden from public discovery / recommendation surfaces (beta hub retains direct access). */
export function isExcludedDiscoveryRoomSlug(
  slug: string | null | undefined
): boolean {
  return String(slug ?? "").trim().toLowerCase() === BETA_ROOM_SLUG
}

export function isPublicDiscoveryRoom(room: {
  slug?: string | null
  show_on_profile?: boolean | null
}): boolean {
  if (isExcludedDiscoveryRoomSlug(room.slug)) return false
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
