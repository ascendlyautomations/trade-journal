import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"

/**
 * Re-check at processing time so stale outbox rows do not disconnect reinstated members.
 * Banned or non-active members must still be removed from LiveKit.
 */
export async function shouldDisconnectLiveKitMember(
  admin: SupabaseClient<Database>,
  roomId: string,
  userId: string
): Promise<boolean> {
  const { data, error } = await admin.rpc("room_livekit_should_disconnect", {
    p_room_id: roomId,
    p_user_id: userId,
  })

  if (error) {
    console.error("[livekit/outbox] should_disconnect rpc failed", error.message)
    throw error
  }

  return Boolean(data)
}
