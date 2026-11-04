import type { SupabaseClient } from "@supabase/supabase-js"
import {
  TRADE_ROOM_DETAIL_SELECT,
  type TradeRoomRow,
} from "@/lib/tradeRoomClient"

/** Matches native `DefaultRoomRepository.memberRoomSelect` (compact field list). */
const MEMBER_ROOM_DETAIL_COMPACT = TRADE_ROOM_DETAIL_SELECT.replace(/,\s+/g, ",")
const MEMBER_ROOM_EMBED_SELECT = `room_id,room:rooms!room_members_room_id_fkey(${MEMBER_ROOM_DETAIL_COMPACT})`

export type MemberRoomRow = TradeRoomRow & {
  avatar_url?: string | null
}

export type MemberRoomsFetchResult = {
  rooms: MemberRoomRow[]
  failed: boolean
  /** Member rows returned but no rooms decoded (embed/RLS); do not wipe cached list. */
  incomplete: boolean
  errorMessage: string | null
  membershipRowCount: number
}

function parseEmbeddedRoom(
  embed: MemberRoomRow | MemberRoomRow[] | null | undefined
): MemberRoomRow | null {
  if (embed == null) return null
  const row = Array.isArray(embed) ? embed[0] : embed
  if (row == null || typeof row !== "object") return null
  const id = (row as { id?: unknown }).id
  if (typeof id !== "string" || !id.trim()) return null
  return row as MemberRoomRow
}

async function fetchRoomsByIds(
  supabase: SupabaseClient,
  roomIds: string[]
): Promise<MemberRoomRow[]> {
  const unique = [...new Set(roomIds.map((id) => id.trim()).filter(Boolean))]
  if (unique.length === 0) return []

  const { data, error } = await supabase
    .from("rooms")
    .select(TRADE_ROOM_DETAIL_SELECT)
    .in("id", unique)

  if (error) {
    console.error("member rooms by id fetch:", error)
    return []
  }

  return (data ?? []) as MemberRoomRow[]
}

function sortMemberRooms(items: MemberRoomRow[], userId: string): MemberRoomRow[] {
  return [...items].sort((a, b) => {
    const aOwn = a.owner_user_id === userId
    const bOwn = b.owner_user_id === userId
    if (aOwn && !bOwn) return -1
    if (!aOwn && bOwn) return 1
    return String(a.name ?? "").localeCompare(String(b.name ?? ""), undefined, {
      sensitivity: "base",
    })
  })
}

/** Native iOS `memberRooms`: embed from `room_members`, merge owned `rooms`, owner-first sort. */
export async function fetchMemberRoomsForSidebar(
  supabase: SupabaseClient,
  userId: string
): Promise<MemberRoomsFetchResult> {
  const { data, error } = await supabase
    .from("room_members")
    .select(MEMBER_ROOM_EMBED_SELECT)
    .eq("user_id", userId)
    .is("left_at", null)

  if (error) {
    console.error("member rooms fetch:", error)
    return {
      rooms: [],
      failed: true,
      incomplete: false,
      errorMessage: error.message ?? "Could not load your Trade Rooms.",
      membershipRowCount: 0,
    }
  }

  type MembershipRow = {
    room_id?: string | null
    room?: MemberRoomRow | MemberRoomRow[] | null
  }

  const memberships = (data ?? []) as MembershipRow[]
  const items: MemberRoomRow[] = []
  const seen = new Set<string>()
  const embedMissingIds: string[] = []

  for (const membership of memberships) {
    const roomId =
      typeof membership.room_id === "string" ? membership.room_id.trim() : ""
    const room = parseEmbeddedRoom(membership.room)
    if (room) {
      if (!seen.has(room.id)) {
        seen.add(room.id)
        items.push(room)
      }
      continue
    }
    if (roomId) embedMissingIds.push(roomId)
  }

  if (embedMissingIds.length > 0) {
    const fallback = await fetchRoomsByIds(supabase, embedMissingIds)
    for (const room of fallback) {
      if (typeof room.id === "string" && room.id.trim() && !seen.has(room.id)) {
        seen.add(room.id)
        items.push(room)
      }
    }
  }

  const { data: ownedRows, error: ownedError } = await supabase
    .from("rooms")
    .select(TRADE_ROOM_DETAIL_SELECT)
    .eq("owner_user_id", userId)

  if (ownedError) {
    console.error("owned rooms fetch:", ownedError)
  } else if (ownedRows?.length) {
    for (const row of ownedRows) {
      const owned = row as MemberRoomRow
      if (typeof owned.id === "string" && owned.id.trim() && !seen.has(owned.id)) {
        seen.add(owned.id)
        items.push(owned)
      }
    }
  }

  const sorted = sortMemberRooms(items, userId)
  const membershipRowCount = memberships.length
  const incomplete = membershipRowCount > 0 && sorted.length === 0

  return {
    rooms: sorted,
    failed: false,
    incomplete,
    errorMessage: incomplete
      ? "Could not load your Trade Rooms."
      : null,
    membershipRowCount,
  }
}

export function upsertMemberRoomInList(
  rooms: MemberRoomRow[],
  room: MemberRoomRow
): MemberRoomRow[] {
  if (typeof room.id !== "string" || !room.id.trim()) return rooms
  const next = rooms.filter((r) => r.id !== room.id)
  next.push(room)
  return next.sort((a, b) =>
    String(a.name ?? "").localeCompare(String(b.name ?? ""))
  )
}

export function removeMemberRoomFromList(
  rooms: MemberRoomRow[],
  roomId: string
): MemberRoomRow[] {
  return rooms.filter((r) => r.id !== roomId)
}
