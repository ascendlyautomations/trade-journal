/** Profile deferred loaders — no automatic fetch on idle Profile mount. */

export const PROFILE_ROOM_SELECT =
  "id, slug, owner_user_id, show_on_profile" as const

export type ProfileRoomRow = {
  id: string
  slug?: string | null
  owner_user_id: string
  show_on_profile?: boolean | null
}

export type ProfileBootstrapSectionCounts = {
  has_active_story?: boolean
  has_room?: boolean
}

export function profileRoomKeyFromRow(
  room: Pick<ProfileRoomRow, "id" | "slug"> | null | undefined
): string | null {
  if (!room) return null
  if (room.slug != null && String(room.slug).trim() !== "") {
    return String(room.slug)
  }
  if (room.id != null) return String(room.id)
  return null
}

export function resolveProfileHasActiveStory(input: {
  bootstrapHasActiveStory: boolean | null | undefined
  storiesByUser: Record<string, unknown[]>
  profileId: string | null | undefined
}): boolean {
  if (input.bootstrapHasActiveStory === true) return true
  if (input.bootstrapHasActiveStory === false) {
    const loaded = input.profileId
      ? (input.storiesByUser[String(input.profileId)]?.length ?? 0) > 0
      : false
    return loaded
  }
  if (!input.profileId) return false
  return (input.storiesByUser[String(input.profileId)]?.length ?? 0) > 0
}

export function resolveProfileHasRoom(input: {
  bootstrapHasRoom: boolean | null | undefined
  roomRow: ProfileRoomRow | null | undefined
}): boolean {
  if (input.roomRow && input.roomRow.owner_user_id) return true
  return input.bootstrapHasRoom === true
}

export function shouldFetchProfileStories(input: {
  storyViewerRequested: boolean
}): boolean {
  return input.storyViewerRequested
}

export function shouldFetchProfileRoom(input: {
  roomNavigationRequested: boolean
}): boolean {
  return input.roomNavigationRequested
}
