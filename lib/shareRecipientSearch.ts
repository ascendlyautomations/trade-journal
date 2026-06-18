import type { SupabaseClient } from "@supabase/supabase-js"
import type { ShareConversationRow } from "./shareToConversations"

export type ShareProfileRow = {
  id: string
  username: string
  name: string | null
  avatar_url: string | null
}

/** Match inbox DM modal profile search (`app/(app)/messages/page.tsx`). */
export async function searchProfilesForShare(
  supabase: SupabaseClient,
  currentUserId: string,
  query: string,
  excludeUserIds: Iterable<string> = []
): Promise<ShareProfileRow[]> {
  const trimmed = query.trim()
  if (!trimmed) return []

  const excluded = new Set(excludeUserIds)
  excluded.add(currentUserId)

  const { data, error } = await supabase
    .from("profiles")
    .select("id, username, name, avatar_url")
    .neq("id", currentUserId)
    .or(`username.ilike.%${trimmed}%,name.ilike.%${trimmed}%`)
    .limit(10)

  if (error) {
    console.error("searchProfilesForShare:", error)
    return []
  }

  return (data || []).filter((row) => !excluded.has(row.id))
}

export function filterShareConversationsByQuery(
  conversations: ShareConversationRow[],
  query: string
): ShareConversationRow[] {
  const trimmed = query.trim().toLowerCase()
  if (!trimmed) return conversations

  return conversations.filter((conv) =>
    conv.name.toLowerCase().includes(trimmed)
  )
}

export function collectDmPartnerUserIds(
  conversations: ShareConversationRow[]
): Set<string> {
  const ids = new Set<string>()
  for (const conv of conversations) {
    if (!conv.is_group && conv.other_user_id) {
      ids.add(conv.other_user_id)
    }
  }
  return ids
}
