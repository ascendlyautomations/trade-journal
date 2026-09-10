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

  return findExistingDmConversationIdBatched(
    client,
    currentUserId,
    otherUserId,
    { skipGroupFilter }
  )
}

/**
 * Batched 1:1 lookup: membership rows → participant sets → optional is_group filter.
 * Replaces per-conversation N+1 participant/conversation queries.
 */
async function findExistingDmConversationIdBatched(
  client: SupabaseClient,
  me: string,
  them: string,
  options: { skipGroupFilter: boolean }
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

  const candidates: string[] = []
  for (const [cid, users] of byConvo) {
    if (users.size === 2 && users.has(me) && users.has(them)) {
      candidates.push(cid)
    }
  }
  if (candidates.length === 0) return null

  if (options.skipGroupFilter) {
    return candidates[0] ?? null
  }

  const { data: meta } = await client
    .from("conversations")
    .select("id, is_group")
    .in("id", candidates)

  for (const conv of meta ?? []) {
    if (!conv.is_group) return conv.id
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
