import { BETA_ROOM_SLUG } from "./betaHub.ts"
import type { PopularTradeRoom } from "./popularTradeRooms.ts"

export type DiscoveryRoomRow = {
  id?: string
  name?: string
  description?: string | null
  slug?: string | null
  member_count?: number | string | null
  image_url?: string | null
  avatar_url?: string | null
  room_kind?: string | null
  is_member?: boolean | null
  owner?: {
    avatar_url?: string | null
  } | null
}

/** Matches native `TradeRoomKind.parse` — only explicit `official` is official. */
export function isOfficialDiscoveryTradeRoom(row: {
  room_kind?: string | null
}): boolean {
  return String(row.room_kind ?? "").trim().toLowerCase() === "official"
}

/** Same drops as native `DefaultExploreRepository.mapDiscoveryRows`. */
export function mapExploreSuggestedDiscoveryRoom(
  row: DiscoveryRoomRow
): PopularTradeRoom | null {
  const id = String(row.id ?? "").trim()
  const name = String(row.name ?? "").trim()
  if (!id || !name) return null

  const slugRaw = String(row.slug ?? "").trim()
  if (slugRaw.toLowerCase() === BETA_ROOM_SLUG) return null

  const slug = slugRaw.length > 0 ? slugRaw : null
  const imageTrimmed = String(row.image_url ?? "").trim()
  const ownerAvatar = String(row.owner?.avatar_url ?? "").trim()
  const imageUrl =
    imageTrimmed.length > 0
      ? imageTrimmed
      : ownerAvatar.length > 0
        ? ownerAvatar
        : row.avatar_url ?? null

  return {
    id,
    name,
    description: row.description ?? null,
    slug: slug ?? id,
    memberCount: Number(row.member_count) || 0,
    imageUrl,
    avatarUrl: row.avatar_url ?? null,
  }
}

export function parseExploreSuggestedDiscoveryRooms(
  raw: unknown
): PopularTradeRoom[] {
  if (!Array.isArray(raw)) return []
  return raw
    .map((row) => mapExploreSuggestedDiscoveryRoom(row as DiscoveryRoomRow))
    .filter((room): room is PopularTradeRoom => room != null)
}

/** Membership exclusion matches native `ExploreViewModel.suggestedTradeRooms`. */
export function isExploreSuggestedRoomEligibleForViewer(
  row: DiscoveryRoomRow
): boolean {
  return row.is_member !== true
}

export function parseExploreSuggestedDiscoveryRoomsForViewer(
  raw: unknown
): PopularTradeRoom[] {
  if (!Array.isArray(raw)) return []
  return raw
    .filter((row) =>
      isExploreSuggestedRoomEligibleForViewer(row as DiscoveryRoomRow)
    )
    .map((row) => mapExploreSuggestedDiscoveryRoom(row as DiscoveryRoomRow))
    .filter((room): room is PopularTradeRoom => room != null)
}

export function mergeExploreCommunityRooms(
  existing: PopularTradeRoom[],
  incoming: PopularTradeRoom[]
): PopularTradeRoom[] {
  if (incoming.length === 0) return existing
  const seen = new Set(existing.map((room) => room.id))
  const merged = [...existing]
  for (const room of incoming) {
    if (seen.has(room.id)) continue
    seen.add(room.id)
    merged.push(room)
  }
  return merged
}

/** @deprecated use isOfficialDiscoveryTradeRoom */
export function isUserCommunityTradeRoom(row: {
  room_kind?: string | null
}): boolean {
  return !isOfficialDiscoveryTradeRoom(row)
}

/** @deprecated use mapExploreSuggestedDiscoveryRoom */
export const mapExploreCommunityDiscoveryRoom = mapExploreSuggestedDiscoveryRoom

/** @deprecated use parseExploreSuggestedDiscoveryRooms */
export const parseExploreCommunityDiscoveryRooms =
  parseExploreSuggestedDiscoveryRooms
