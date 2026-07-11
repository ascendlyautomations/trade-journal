import type { SupabaseClient } from "@supabase/supabase-js"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

export type RoomSectionLike = { id: string; name?: string | null }

/** Default ON when no preference row exists. */
export function channelNotificationsEnabled(
  prefsBySectionId: Record<string, boolean | undefined>,
  sectionId: string
): boolean {
  const value = prefsBySectionId[sectionId]
  return value !== false
}

export async function fetchRoomChannelNotificationPrefs(
  supabase: SupabaseClient,
  roomId: string,
  userId: string,
  sections: RoomSectionLike[]
): Promise<Record<string, boolean>> {
  const result: Record<string, boolean> = {}
  for (const section of sections) {
    result[section.id] = true
  }

  if (sections.length === 0) return result

  const { data, error } = await supabase
    .from("room_member_channel_preferences")
    .select("section_id, notifications_enabled")
    .eq("room_id", roomId)
    .eq("user_id", userId)

  if (error) {
    console.error("fetchRoomChannelNotificationPrefs:", error)
    return result
  }

  for (const row of data ?? []) {
    const sectionId = String(row.section_id)
    if (sectionId in result) {
      result[sectionId] = row.notifications_enabled !== false
    }
  }

  return result
}

export async function upsertRoomChannelNotificationPref(
  supabase: SupabaseClient,
  roomId: string,
  userId: string,
  sectionId: string,
  notificationsEnabled: boolean
): Promise<{ ok: boolean; error?: string }> {
  const { error } = await supabase
    .from("room_member_channel_preferences")
    .upsert(
      {
        user_id: userId,
        room_id: roomId,
        section_id: sectionId,
        notifications_enabled: notificationsEnabled,
      },
      { onConflict: "user_id,room_id,section_id" }
    )

  if (error) {
    console.error("upsertRoomChannelNotificationPref:", error)
    return { ok: false, error: toUserFacingErrorMessage(error) }
  }

  return { ok: true }
}

export function anyRoomChannelNotificationsEnabled(
  roomLevelEnabled: boolean,
  sections: RoomSectionLike[],
  prefsBySectionId: Record<string, boolean | undefined>
): boolean {
  if (!roomLevelEnabled) return false
  if (sections.length === 0) return true
  return sections.some((section) =>
    channelNotificationsEnabled(prefsBySectionId, section.id)
  )
}
