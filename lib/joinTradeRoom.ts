import type { SupabaseClient } from "@supabase/supabase-js"
import { createRoomJoinNotification } from "@/lib/createRoomJoinNotification"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import { clearRoomSessionsForUser } from "@/lib/roomSessionCache"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { hapticMedium } from "@/lib/nativeHaptics"

export type JoinTradeRoomResult =
  | { ok: true; alreadyMember: boolean }
  | { ok: false; error: string }

/** Join or reactivate membership in a trade room (same rules as community joinRoom). */
export async function joinTradeRoom(
  supabase: SupabaseClient,
  roomId: string,
  userId: string
): Promise<JoinTradeRoomResult> {
  const { data: existing } = await supabase
    .from("room_members")
    .select("id, left_at")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .maybeSingle()

  const alreadyActive = existing != null && existing.left_at == null

  if (!existing) {
    const { error } = await supabase.from("room_members").insert({
      room_id: roomId,
      user_id: userId,
      notification_enabled: true,
    })

    if (error) {
      if (error.code === "23505") {
        const reactivated = await reactivateRoomMembership(
          supabase,
          roomId,
          userId
        )
        if (!reactivated.ok) return reactivated
      } else {
        console.error("joinTradeRoom insert:", error)
        return { ok: false, error: toUserFacingErrorMessage(error) }
      }
    }
  } else if (!alreadyActive) {
    const reactivated = await reactivateRoomMembership(supabase, roomId, userId)
    if (!reactivated.ok) return reactivated
  }

  if (!alreadyActive) {
    clearRoomSessionsForUser(userId)
    await createRoomJoinNotification(supabase, roomId)
    notifyGettingStartedChecklistMaybeCompleted()
  }

  hapticMedium("join-room")
  return { ok: true, alreadyMember: alreadyActive }
}

async function reactivateRoomMembership(
  supabase: SupabaseClient,
  roomId: string,
  userId: string
): Promise<JoinTradeRoomResult> {
  const { error } = await supabase
    .from("room_members")
    .update({ left_at: null, notification_enabled: true })
    .eq("room_id", roomId)
    .eq("user_id", userId)

  if (error) {
    console.error("joinTradeRoom reactivate:", error)
    return { ok: false, error: toUserFacingErrorMessage(error) }
  }
  return { ok: true, alreadyMember: false }
}
