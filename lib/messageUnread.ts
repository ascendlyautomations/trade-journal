import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "./supabaseClient"
import { isDemoUserId } from "./demo/constants"
import {
  getDemoUnreadCountForConversation,
  getDemoUnreadMessageCount,
  getDemoUnreadMessageRows,
} from "./demo/demoMessages"
import { isDemoSupabaseBlocked } from "./demo/demoSupabaseGuard"

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
  if (isDemoSupabaseBlocked() && isDemoUserId(userId)) {
    return getDemoUnreadMessageRows(userId, conversationIds)
  }

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
  if (isDemoSupabaseBlocked() && isDemoUserId(userId)) {
    return getDemoUnreadCountForConversation(userId, conversationId)
  }
  const rows = await fetchUnreadMessageRows(userId, [conversationId], client)
  return countUnreadFromRows(rows, userId)
}

/** Total unread DM/conversation messages for Navbar badge. */
export async function fetchTotalUnreadMessageCount(
  userId: string,
  client: SupabaseClient = supabase
): Promise<number> {
  if (isDemoSupabaseBlocked() && isDemoUserId(userId)) {
    return getDemoUnreadMessageCount(userId)
  }
  const conversationIds = await fetchParticipantConversationIds(userId, client)
  if (!conversationIds.length) return 0

  const rows = await fetchUnreadMessageRows(userId, conversationIds, client)
  return countUnreadFromRows(rows, userId)
}

export type MarkConversationUnreadResult =
  | { ok: true; messageId: string; unreadCount: number }
  | { ok: false; reason: "no_message" | "error"; error?: unknown }

/** Mark a conversation unread by removing the current user from seen_by on the latest inbound message only. */
export async function markConversationUnread(
  userId: string,
  conversationId: string,
  client: SupabaseClient = supabase
): Promise<MarkConversationUnreadResult> {
  if (isDemoSupabaseBlocked()) {
    return { ok: false, reason: "no_message" }
  }
  const { data: rows, error: fetchErr } = await client
    .from("messages")
    .select("id, sender_id, seen_by, created_at")
    .eq("conversation_id", conversationId)
    .not("sender_id", "is", null)
    .neq("sender_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)

  if (fetchErr) {
    console.error("[messageUnread] markConversationUnread fetch:", fetchErr)
    return { ok: false, reason: "error", error: fetchErr }
  }

  const target = rows?.[0]
  if (!target) {
    return { ok: false, reason: "no_message" }
  }

  const seenBy = normalizeSeenBy(target.seen_by)
  const nextSeenBy = seenBy.filter((id) => id !== userId)

  const { error: updateErr } = await client
    .from("messages")
    .update({ seen_by: nextSeenBy })
    .eq("id", target.id)

  if (updateErr) {
    console.error("[messageUnread] markConversationUnread update:", updateErr)
    return { ok: false, reason: "error", error: updateErr }
  }

  const unreadCount = await fetchUnreadCountForConversation(
    userId,
    conversationId,
    client
  )

  return { ok: true, messageId: target.id, unreadCount }
}

export function dispatchUnreadMessagesRefresh() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new CustomEvent("tj-unread-messages-refresh"))
}
