import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { processBroadcasterDisconnectChecks } from "./tradeRoomBroadcastDisconnectCheck.ts"

export async function processLiveKitBroadcastDisconnectChecks(
  admin: SupabaseClient<Database>,
  options: { roomId?: string; sessionId?: string; limit?: number } = {}
) {
  return processBroadcasterDisconnectChecks(admin, options)
}
