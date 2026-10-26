import type { SupabaseClient } from "@supabase/supabase-js"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

export type BanTradeRoomMemberResult =
  | { ok: true }
  | { ok: false; error: string }

/** Atomic ban + soft-remove — ``rpc_v1_ban_trade_room_member``. */
export async function banTradeRoomMember(
  supabase: SupabaseClient,
  roomId: string,
  targetUserId: string
): Promise<BanTradeRoomMemberResult> {
  const { error } = await supabase.rpc("rpc_v1_ban_trade_room_member", {
    p_room_id: roomId,
    p_user_id: targetUserId,
  })

  if (error) {
    console.error("banTradeRoomMember:", error)
    return { ok: false, error: toUserFacingErrorMessage(error) }
  }

  return { ok: true }
}
