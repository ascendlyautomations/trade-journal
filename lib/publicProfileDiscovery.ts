import type { SupabaseClient } from "@supabase/supabase-js"

/** Profiles that may appear on public discovery surfaces (explore, search, leaderboards, feed). */
export function isPublicDiscoverableProfile(
  profile: { is_private?: boolean | null } | null | undefined
): boolean {
  return profile?.is_private !== true
}

export async function fetchPrivateProfileOwnerIds(
  supabase: SupabaseClient,
  userIds: Array<string | null | undefined>
): Promise<Set<string>> {
  const unique = [...new Set(userIds.filter(Boolean).map((id) => String(id)))]
  if (unique.length === 0) return new Set()

  const { data, error } = await supabase
    .from("profiles")
    .select("id")
    .in("id", unique)
    .eq("is_private", true)

  if (error) {
    console.warn("[publicProfileDiscovery] private owner lookup:", error.message)
    return new Set()
  }

  return new Set((data ?? []).map((row) => String(row.id)))
}

/** Drop rooms whose owner has a private profile (public discovery only). */
export async function filterRoomsWithPublicOwners<
  T extends { owner_user_id?: string | null },
>(supabase: SupabaseClient, rooms: T[]): Promise<T[]> {
  const privateOwnerIds = await fetchPrivateProfileOwnerIds(
    supabase,
    rooms.map((room) => room.owner_user_id)
  )
  if (privateOwnerIds.size === 0) return rooms

  return rooms.filter(
    (room) =>
      !room.owner_user_id || !privateOwnerIds.has(String(room.owner_user_id))
  )
}
