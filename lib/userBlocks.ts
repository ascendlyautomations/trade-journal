import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "@/lib/supabaseClient"

export type UserBlockStatus = {
  otherUserId: string
  blockedByMe: boolean
  blockedByOther: boolean
}

function normalizeUserBlockStatus(raw: unknown): UserBlockStatus | null {
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

export async function fetchUserBlockStatus(
  otherUserId: string,
  client: SupabaseClient = supabase
): Promise<
  | { ok: true; status: UserBlockStatus }
  | { ok: false; message: string }
> {
  const id = String(otherUserId ?? "").trim()
  if (!id) {
    return { ok: false, message: "Invalid user." }
  }
  const { data, error } = await client.rpc("get_user_block_status", {
    p_other_user_id: id,
  })
  if (error) {
    return { ok: false, message: error.message }
  }
  const status = normalizeUserBlockStatus(data)
  return status
    ? { ok: true, status }
    : { ok: false, message: "Could not determine block status." }
}

export async function setUserBlocked(
  otherUserId: string,
  blocked: boolean,
  client: SupabaseClient = supabase
): Promise<
  | { ok: true; status: UserBlockStatus }
  | { ok: false; message: string }
> {
  const id = String(otherUserId ?? "").trim()
  if (!id) {
    return { ok: false, message: "Invalid user." }
  }
  const { data, error } = await client.rpc("set_user_block", {
    p_blocked_id: id,
    p_blocked: blocked,
  })
  if (error) {
    return { ok: false, message: error.message }
  }
  const status = normalizeUserBlockStatus(data)
  return status
    ? { ok: true, status }
    : { ok: false, message: "Could not update block status." }
}
