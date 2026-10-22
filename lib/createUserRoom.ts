import { supabase } from "@/lib/supabaseClient"
import { defaultTradeRoomDraft } from "@/lib/tradeRoomConfiguration"
import { createTradeRoomViaRpc } from "@/lib/tradeRoomClient"

/** @deprecated Prefer TradeRoomCreateWizard + createTradeRoomViaRpc. */
export async function createUserRoom(userId: string, username: string) {
  const draft = defaultTradeRoomDraft(username)
  const { room, error } = await createTradeRoomViaRpc(supabase, userId, draft)
  if (error || !room) {
    console.error("Create room error:", error)
    throw new Error(error ?? "Failed to create room")
  }
  return room
}
