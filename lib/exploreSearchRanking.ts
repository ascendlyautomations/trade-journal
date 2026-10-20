import type { PopularTradeRoom } from "@/lib/popularTradeRooms"

function normalizeQuery(query: string): string {
  return query.trim().toLowerCase()
}

/** Lower tier = stronger match (aligned with iOS ExploreTraderRanking). */
export function exploreProfileSearchMatchTier(
  query: string,
  username: string | null | undefined,
  name: string | null | undefined
): number {
  const q = normalizeQuery(query)
  if (!q) return 5
  const user = (username ?? "").trim().toLowerCase()
  const display = (name ?? "").trim().toLowerCase()
  if (user === q) return 0
  if (user.startsWith(q)) return 1
  if (display === q) return 2
  if (display.includes(q)) return 3
  if (user.includes(q)) return 4
  return 5
}

export function sortExploreProfileSearchResults<
  T extends { username?: string | null; name?: string | null },
>(items: T[], query: string): T[] {
  return items
    .map((item, index) => ({ item, index }))
    .sort((a, b) => {
      const left = exploreProfileSearchMatchTier(
        query,
        a.item.username,
        a.item.name
      )
      const right = exploreProfileSearchMatchTier(
        query,
        b.item.username,
        b.item.name
      )
      if (left !== right) return left - right
      return a.index - b.index
    })
    .map(({ item }) => item)
}

export function exploreRoomSearchMatchTier(
  query: string,
  name: string,
  slug: string | null | undefined
): number {
  const q = normalizeQuery(query)
  if (!q) return 5
  const roomName = name.trim().toLowerCase()
  const roomSlug = (slug ?? "").trim().toLowerCase()
  if (roomName === q || roomSlug === q) return 0
  if (roomName.startsWith(q) || roomSlug.startsWith(q)) return 1
  if (roomName.includes(q)) return 2
  if (roomSlug.includes(q)) return 3
  return 4
}

export function sortExploreRoomSearchResults(
  rooms: PopularTradeRoom[],
  query: string
): PopularTradeRoom[] {
  return rooms
    .map((room, index) => ({ room, index }))
    .sort((a, b) => {
      const left = exploreRoomSearchMatchTier(
        query,
        a.room.name,
        a.room.slug
      )
      const right = exploreRoomSearchMatchTier(
        query,
        b.room.name,
        b.room.slug
      )
      if (left !== right) return left - right
      return a.index - b.index
    })
    .map(({ room }) => room)
}
