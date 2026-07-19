import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"
import { newConversationId } from "./conversationAccess"

export type FindExistingDmConversationOptions = {
  /**
   * When true, any 2-participant conversation matches (profile Message button).
   * When false, group conversations are skipped (messages inbox DM modal).
   */
  skipGroupFilter?: boolean
}

export type EnsureDmConversationResult =
  | { ok: true; conversationId: string; existing: boolean }
  | {
      ok: false
      error: PostgrestError
      phase: "conversation" | "participants"
      conversationId?: string
    }

/** Find an existing 1:1 DM conversation between two users, if any. */
export async function findExistingDmConversationId(
  client: SupabaseClient,
  currentUserId: string,
  otherUserId: string,
  options: FindExistingDmConversationOptions = {}
): Promise<string | null> {
  const { skipGroupFilter = false } = options
  if (!currentUserId || !otherUserId || currentUserId === otherUserId) {
    return null
  }

  if (skipGroupFilter) {
    return findExistingDmConversationIdProfileStyle(
      client,
      currentUserId,
      otherUserId
    )
  }

  return findExistingDmConversationIdMessagesStyle(
    client,
    currentUserId,
    otherUserId
  )
}

/** Inbox DM modal: skip group conversations. */
async function findExistingDmConversationIdMessagesStyle(
  client: SupabaseClient,
  currentUserId: string,
  otherUserId: string
): Promise<string | null> {
  const { data: myRows } = await client
    .from("conversation_participants")
    .select("conversation_id")
    .eq("user_id", currentUserId)

  const ids = [...new Set(myRows?.map((r) => r.conversation_id) || [])]
  for (const convoId of ids) {
    const { data: meta } = await client
      .from("conversations")
      .select("id, is_group")
      .eq("id", convoId)
      .maybeSingle()

    if (!meta || meta.is_group) continue

    const { data: parts } = await client
      .from("conversation_participants")
      .select("user_id")
      .eq("conversation_id", convoId)

    const uidSet = new Set(parts?.map((p) => p.user_id))
    if (
      uidSet.size === 2 &&
      uidSet.has(currentUserId) &&
      uidSet.has(otherUserId)
    ) {
      return convoId
    }
  }
  return null
}

/** Profile Message button: batch lookup, no is_group filter (legacy behavior). */
async function findExistingDmConversationIdProfileStyle(
  client: SupabaseClient,
  me: string,
  them: string
): Promise<string | null> {
  const { data: mine } = await client
    .from("conversation_participants")
    .select("conversation_id")
    .eq("user_id", me)

  const ids = [...new Set(mine?.map((r) => r.conversation_id) ?? [])]
  if (ids.length === 0) return null

  const { data: rows } = await client
    .from("conversation_participants")
    .select("conversation_id, user_id")
    .in("conversation_id", ids)

  const byConvo = new Map<string, Set<string>>()
  for (const row of rows ?? []) {
    if (!byConvo.has(row.conversation_id)) {
      byConvo.set(row.conversation_id, new Set())
    }
    byConvo.get(row.conversation_id)!.add(row.user_id)
  }

  for (const [cid, users] of byConvo) {
    if (users.size === 2 && users.has(me) && users.has(them)) return cid
  }

  return null
}

/**
 * Return an existing DM conversation id or create conversation shell + participants.
 * Does not navigate or update UI — callers keep their own logging and routing.
 */
export async function ensureDmConversation(
  client: SupabaseClient,
  currentUserId: string,
  otherUserId: string,
  options: FindExistingDmConversationOptions = {}
): Promise<EnsureDmConversationResult> {
  if (!currentUserId || !otherUserId || currentUserId === otherUserId) {
    return {
      ok: false,
      error: { message: "Invalid DM participants" } as PostgrestError,
      phase: "conversation",
    }
  }

  const existingId = await findExistingDmConversationId(
    client,
    currentUserId,
    otherUserId,
    options
  )
  if (existingId) {
    return { ok: true, conversationId: existingId, existing: true }
  }

  const { data: blocked } = await client.rpc("users_have_active_block", {
    p_user_a: currentUserId,
    p_user_b: otherUserId,
  })
  if (blocked === true) {
    return {
      ok: false,
      error: {
        message: "Direct messaging is unavailable while a user block is active.",
        code: "P0001",
      } as PostgrestError,
      phase: "conversation",
    }
  }

  const conversationId = newConversationId()
  const dmConvoPayload = { id: conversationId, is_group: false as const }

  const { error: convoErr } = await client
    .from("conversations")
    .insert(dmConvoPayload)

  if (convoErr) {
    return {
      ok: false,
      error: convoErr,
      phase: "conversation",
      conversationId,
    }
  }

  const dmParticipantsPayload = [
    { conversation_id: conversationId, user_id: currentUserId },
    { conversation_id: conversationId, user_id: otherUserId },
  ]

  const { error: participantsErr } = await client
    .from("conversation_participants")
    .insert(dmParticipantsPayload)

  if (participantsErr) {
    return {
      ok: false,
      error: participantsErr,
      phase: "participants",
      conversationId,
    }
  }

  return { ok: true, conversationId, existing: false }
}
