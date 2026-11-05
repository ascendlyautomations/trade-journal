import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { isLiveKitConfigured } from "./config.ts"
import { disconnectUserFromTradeRoomLiveKit } from "./liveKitRoomService.ts"

/**
 * Best-effort immediate LiveKit disconnect (ban/kick/leave).
 * Database triggers also enqueue `room_livekit_disconnect_outbox` for cron retry.
 */
export async function disconnectTradeRoomMemberFromLiveKit(
  admin: SupabaseClient<Database>,
  roomId: string,
  userId: string,
  reason: string
): Promise<void> {
  if (!isLiveKitConfigured()) return

  const result = await disconnectUserFromTradeRoomLiveKit(
    admin,
    roomId,
    userId
  )

  if (result.errors.length > 0) {
    console.warn("[livekit/disconnect] partial failure", {
      roomId,
      userId,
      reason,
      errors: result.errors,
    })
  }
}
