export const BETA_ROOM_SLUG = "tradetraxs-beta"
export const BETA_ANNOUNCEMENTS_SECTION = "announcements"

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
