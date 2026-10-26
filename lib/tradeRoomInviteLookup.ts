import type { SupabaseClient } from "@supabase/supabase-js"
import {
  TRADE_ROOM_DETAIL_SELECT,
  type TradeRoomRow,
} from "@/lib/tradeRoomClient"

const INVITE_LOOKUP_FIELDS = TRADE_ROOM_DETAIL_SELECT.split(", ").map((f) => f.trim())

function pickTradeRoomRow(raw: Record<string, unknown> | null): TradeRoomRow | null {
  if (!raw || typeof raw !== "object" || !raw.id) return null
  const row: Record<string, unknown> = {}
  for (const key of INVITE_LOOKUP_FIELDS) {
    if (key in raw) row[key] = raw[key]
  }
  return row as TradeRoomRow
}

/** Resolve a Trade Room by invite slug or UUID when direct `rooms` SELECT is restricted. */
export async function fetchTradeRoomInviteLookup(
  supabase: SupabaseClient,
  ref: string
): Promise<TradeRoomRow | null> {
  const trimmed = String(ref ?? "").trim()
  if (!trimmed) return null

  const { data, error } = await supabase.rpc("rpc_v1_trade_room_invite_lookup", {
    p_ref: trimmed,
  })

  if (error) {
    console.error("[tradeRoom] invite lookup RPC:", error)
    return null
  }

  if (data == null) return null
  if (typeof data === "object" && !Array.isArray(data)) {
    return pickTradeRoomRow(data as Record<string, unknown>)
  }
  return null
}
