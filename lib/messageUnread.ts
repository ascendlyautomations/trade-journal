import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "./supabaseClient"
import { isDemoUserId } from "./demo/constants"
import {
  getDemoUnreadCountForConversation,
  getDemoUnreadMessageCount,
  getDemoUnreadMessageRows,
} from "./demo/demoMessages"
import { isDemoSupabaseBlocked } from "./demo/demoSupabaseGuard"
import { fetchMutedConversationIds } from "./conversationMemberPreferences"
import { fetchHiddenBlockedDmConversationIds } from "./conversationBlocks"

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

function isMissingReadCursorRpc(error: {
  code?: string
  message?: string
}): boolean {
  const message = String(error.message ?? "").toLowerCase()
  return (
    error.code === "PGRST202" ||
    error.code === "42883" ||
    message.includes("could not find the function") ||
    message.includes("schema cache")
  )
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
  const [{ data, error }, hiddenBlockedConversationIds] = await Promise.all([
    client
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", userId),
    fetchHiddenBlockedDmConversationIds(client),
  ])

  if (error || !data?.length) return []

  return [
    ...new Set(
      data
        .map((row) => row.conversation_id as string)
        .filter((id) => !hiddenBlockedConversationIds.has(id))
    ),
  ]
}

async function fetchCursorUnreadCounts(
  conversationIds: string[],
  client: SupabaseClient
): Promise<Map<string, number> | null> {
  if (!conversationIds.length) return new Map()
  const { data, error } = await client.rpc("get_conversation_unread_counts", {
    p_conversation_ids: conversationIds,
  })
  if (error) {
    if (isMissingReadCursorRpc(error)) return null
    console.error("[messageUnread] cursor unread counts:", error)
    return new Map()
  }

  return new Map(
    ((data ?? []) as Array<{ conversation_id: string; unread_count: number | string }>).map(
      (row) => [String(row.conversation_id), Number(row.unread_count) || 0]
    )
  )
}

/** Batch unread counts, using read cursors with a legacy seen_by fallback. */
export async function fetchUnreadCountsForConversations(
  userId: string,
  conversationIds: string[],
  client: SupabaseClient = supabase
): Promise<Record<string, number>> {
  const result = Object.fromEntries(conversationIds.map((id) => [id, 0]))
  if (!conversationIds.length) return result

  const cursorCounts = await fetchCursorUnreadCounts(conversationIds, client)
  if (cursorCounts) {
    for (const id of conversationIds) result[id] = cursorCounts.get(id) ?? 0
    return result
  }

  const rows = await fetchUnreadMessageRows(userId, conversationIds, client)
  for (const row of rows) {
    if (!row.sender_id || row.sender_id === userId) continue
    if (normalizeSeenBy(row.seen_by).includes(userId)) continue
    result[row.conversation_id] = (result[row.conversation_id] ?? 0) + 1
  }
  return result
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
  client: SupabaseClient = supabase,
  options?: { ignoreMute?: boolean }
): Promise<number> {
  if (!options?.ignoreMute) {
    const muted = await fetchMutedConversationIds(
      userId,
      [conversationId],
      client
    )
    if (muted.has(conversationId)) return 0
  }

  if (isDemoSupabaseBlocked() && isDemoUserId(userId)) {
    return getDemoUnreadCountForConversation(userId, conversationId)
  }
  const hidden = await fetchHiddenBlockedDmConversationIds(client)
  if (hidden.has(conversationId)) return 0
  const cursorCounts = await fetchCursorUnreadCounts([conversationId], client)
  if (cursorCounts) {
    return cursorCounts.get(conversationId) ?? 0
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

  const muted = await fetchMutedConversationIds(userId, conversationIds, client)
  const activeIds = conversationIds.filter((id) => !muted.has(id))
  if (!activeIds.length) return 0

  const cursorCounts = await fetchCursorUnreadCounts(activeIds, client)
  if (cursorCounts) {
    let total = 0
    for (const id of activeIds) total += cursorCounts.get(id) ?? 0
    return total
  }

  const rows = await fetchUnreadMessageRows(userId, activeIds, client)
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

  const { data: cursorMessageId, error: cursorError } = await client.rpc(
    "mark_conversation_unread",
    { p_conversation_id: conversationId }
  )
  if (!cursorError) {
    const messageId =
      typeof cursorMessageId === "string" ? cursorMessageId : null
    if (!messageId) return { ok: false, reason: "no_message" }
    const unreadCount = await fetchUnreadCountForConversation(
      userId,
      conversationId,
      client
    )
    return { ok: true, messageId, unreadCount }
  }

  if (!isMissingReadCursorRpc(cursorError)) {
    console.error("[messageUnread] mark unread cursor:", cursorError)
    return { ok: false, reason: "error", error: cursorError }
  }

  // Deployment-safe fallback only until the cursor RPC is available.
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
