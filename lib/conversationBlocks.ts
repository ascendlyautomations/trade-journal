import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "@/lib/supabaseClient"

export type DmBlockStatus = {
  otherUserId: string
  blockedByMe: boolean
  blockedByOther: boolean
}

function normalizeStatus(raw: unknown): DmBlockStatus | null {
  const row = Array.isArray(raw) ? raw[0] : raw
  if (!row || typeof row !== "object") return null
  const value = row as Record<string, unknown>
  const otherUserId = String(value.other_user_id ?? "").trim()
  if (!otherUserId) return null
  return {
    otherUserId,
    blockedByMe: value.blocked_by_me === true,
    blockedByOther: value.blocked_by_other === true,
  }
}

export async function fetchDmBlockStatus(
  conversationId: string,
  client: SupabaseClient = supabase
): Promise<
  | { ok: true; status: DmBlockStatus }
  | { ok: false; message: string }
> {
  const { data, error } = await client.rpc("get_dm_block_status", {
    p_conversation_id: conversationId,
  })
  if (error) {
    return { ok: false, message: error.message }
  }
  const status = normalizeStatus(data)
  return status
    ? { ok: true, status }
    : { ok: false, message: "Could not determine block status." }
}

export async function setDmUserBlocked(
  conversationId: string,
  blocked: boolean,
  client: SupabaseClient = supabase
): Promise<
  | { ok: true; status: DmBlockStatus }
  | { ok: false; message: string }
> {
  const { data, error } = await client.rpc("set_dm_user_block", {
    p_conversation_id: conversationId,
    p_blocked: blocked,
  })
  if (error) {
    return { ok: false, message: error.message }
  }
  const status = normalizeStatus(data)
  return status
    ? { ok: true, status }
    : { ok: false, message: "Could not update block status." }
}

export async function fetchHiddenBlockedDmConversationIds(
  client: SupabaseClient = supabase
): Promise<Set<string>> {
  const { data, error } = await client.rpc(
    "get_hidden_blocked_dm_conversation_ids"
  )
  if (error) {
    console.error("[conversationBlocks] hidden conversations:", error)
    return new Set()
  }
  return new Set(
    (data ?? [])
      .map((row: { conversation_id?: unknown }) =>
        String(row.conversation_id ?? "").trim()
      )
      .filter(Boolean)
  )
}
