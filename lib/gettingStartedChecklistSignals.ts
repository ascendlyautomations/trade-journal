import type { SupabaseClient } from "@supabase/supabase-js"

export type GettingStartedChecklistSignals = {
  profilePostCount: number
  feedPostCount: number
  followCount: number
  joinedOtherRoom: boolean
}

export async function fetchGettingStartedChecklistSignals(
  supabase: SupabaseClient,
  userId: string
): Promise<GettingStartedChecklistSignals> {
  const [profilePostsRes, feedPostsRes, followRes, roomMembersRes] =
    await Promise.all([
      supabase
        .from("profile_posts")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId),
      supabase
        .from("posts")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId),
      supabase
        .from("followers")
        .select("following_id", { count: "exact", head: true })
        .eq("follower_id", userId),
      supabase
        .from("room_members")
        .select("room_id, rooms(owner_user_id)")
        .eq("user_id", userId)
        .is("left_at", null),
    ])

  const joinedOtherRoom = (roomMembersRes.data ?? []).some(
    (row: {
      rooms?:
        | { owner_user_id?: string }
        | { owner_user_id?: string }[]
        | null
    }) => {
      const rooms = row.rooms
      const ownerId = Array.isArray(rooms)
        ? rooms[0]?.owner_user_id
        : rooms?.owner_user_id
      return ownerId != null && ownerId !== userId
    }
  )

  return {
    profilePostCount: profilePostsRes.count ?? 0,
    feedPostCount: feedPostsRes.count ?? 0,
    followCount: followRes.count ?? 0,
    joinedOtherRoom,
  }
}
