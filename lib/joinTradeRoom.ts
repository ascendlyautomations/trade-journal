import type { SupabaseClient } from "@supabase/supabase-js"
import { createRoomJoinNotification } from "@/lib/createRoomJoinNotification"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"

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
    })

    if (error && error.code !== "23505") {
      console.error("joinTradeRoom insert:", error)
      return { ok: false, error: error.message }
    }
  } else if (!alreadyActive) {
    const { error } = await supabase
      .from("room_members")
      .update({ left_at: null })
      .eq("room_id", roomId)
      .eq("user_id", userId)

    if (error) {
      console.error("joinTradeRoom reactivate:", error)
      return { ok: false, error: error.message }
    }
  }

  if (!alreadyActive) {
    await createRoomJoinNotification(supabase, roomId)
    notifyGettingStartedChecklistMaybeCompleted()
  }

  return { ok: true, alreadyMember: alreadyActive }
}
