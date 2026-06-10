import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "./supabaseClient"

export function normalizeSeenBy(raw: unknown): string[] {
  if (Array.isArray(raw)) return raw.map(String)
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw)
      if (Array.isArray(parsed)) return parsed.map(String)
    } catch {
      return []
    }
  }
  return []
}

export function countUnreadFromRows(
  rows: { seen_by: unknown; sender_id: string | null }[] | null | undefined,
  userId: string
): number {
  let count = 0
  for (const m of rows || []) {
    if (!m.sender_id || m.sender_id === userId) continue
    const seen = normalizeSeenBy(m.seen_by)
    if (seen.includes(userId)) continue
    count += 1
  }
  return count
}

async function fetchParticipantConversationIds(
  userId: string,
  client: SupabaseClient
): Promise<string[]> {
  const { data, error } = await client
    .from("conversation_participants")
    .select("conversation_id")
    .eq("user_id", userId)

  if (error || !data?.length) return []

  return [...new Set(data.map((row) => row.conversation_id as string))]
}

/** Unread rows for conversations the user participates in (same filters as messages list). */
export async function fetchUnreadMessageRows(
  userId: string,
  conversationIds: string[],
  client: SupabaseClient = supabase
): Promise<{ conversation_id: string; seen_by: unknown; sender_id: string | null }[]> {
  if (!conversationIds.length) return []

  const { data, error } = await client
    .from("messages")
    .select("conversation_id, seen_by, sender_id")
    .in("conversation_id", conversationIds)
    .not("sender_id", "is", null)
    .neq("sender_id", userId)

  if (error) {
    console.error("[messageUnread] fetchUnreadMessageRows:", error)
    return []
  }

  return data || []
}

/** Per-conversation unread count (matches `fetchUnreadCountForConversation` on messages list). */
export async function fetchUnreadCountForConversation(
  userId: string,
  conversationId: string,
  client: SupabaseClient = supabase
): Promise<number> {
  const rows = await fetchUnreadMessageRows(userId, [conversationId], client)
  return countUnreadFromRows(rows, userId)
}

/** Total unread DM/conversation messages for Navbar badge. */
export async function fetchTotalUnreadMessageCount(
  userId: string,
  client: SupabaseClient = supabase
): Promise<number> {
  const conversationIds = await fetchParticipantConversationIds(userId, client)
  if (!conversationIds.length) return 0

  const rows = await fetchUnreadMessageRows(userId, conversationIds, client)
  return countUnreadFromRows(rows, userId)
}
