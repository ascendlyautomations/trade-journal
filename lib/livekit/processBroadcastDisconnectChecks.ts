import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { processBroadcasterDisconnectChecks } from "./tradeRoomBroadcastDisconnectCheck.ts"
import { processBroadcastDurationExpirations } from "./tradeRoomBroadcastDurationExpiry.ts"

export async function processLiveKitBroadcastDisconnectChecks(
  admin: SupabaseClient<Database>,
  options: { roomId?: string; sessionId?: string; limit?: number } = {}
) {
  const duration = await processBroadcastDurationExpirations(admin, options)
  const disconnect = await processBroadcasterDisconnectChecks(admin, options)
  return { duration, disconnect }
}
