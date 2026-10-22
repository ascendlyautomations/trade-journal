import type { SupabaseClient } from "@supabase/supabase-js"
import { joinTradeRoom } from "@/lib/joinTradeRoom"
import {
  fetchViewerTradeRoomJoinRequest,
  isUserBannedFromRoom,
  notifyTradeRoomJoinRequestAfterCreate,
  requestTradeRoomJoin,
  type TradeRoomRow,
} from "@/lib/tradeRoomClient"

export type TradeRoomJoinAttemptResult =
  | { kind: "joined"; alreadyMember: boolean }
  | { kind: "requested"; status: string }
  | { kind: "pending"; status: string }
  | { kind: "banned" }
  | { kind: "error"; message: string }

export function roomRequiresJoinApproval(room: Pick<TradeRoomRow, "join_policy" | "is_private">): boolean {
  if (room.is_private) return false
  return String(room.join_policy ?? "open").toLowerCase() === "approval"
}

export async function attemptTradeRoomJoin(
  supabase: SupabaseClient,
  userId: string,
  room: TradeRoomRow
): Promise<TradeRoomJoinAttemptResult> {
  if (await isUserBannedFromRoom(supabase, room.id, userId)) {
    return { kind: "banned" }
  }

  if (roomRequiresJoinApproval(room)) {
    const existing = await fetchViewerTradeRoomJoinRequest(supabase, room.id)
    if (existing === "pending") {
      return { kind: "pending", status: existing }
    }
    if (existing === "approved") {
      const joined = await joinTradeRoom(supabase, room.id, userId)
      if (!joined.ok) return { kind: "error", message: joined.error }
      return { kind: "joined", alreadyMember: joined.alreadyMember }
    }

    const { requestId, status, error } = await requestTradeRoomJoin(supabase, room.id)
    if (error) return { kind: "error", message: error }
    if (requestId && status === "pending") {
      void notifyTradeRoomJoinRequestAfterCreate(room.id, requestId)
    }
    return { kind: "requested", status: status ?? "pending" }
  }

  const joined = await joinTradeRoom(supabase, room.id, userId)
  if (!joined.ok) return { kind: "error", message: joined.error }
  return { kind: "joined", alreadyMember: joined.alreadyMember }
}
