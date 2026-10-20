import type { SupabaseClient } from "@supabase/supabase-js"
import { setConversationNotificationsEnabled } from "@/lib/conversationMemberPreferences"
import { supabase } from "@/lib/supabaseClient"
import type { ContentReportRow } from "@/lib/contentReports"

export type BlockedAccountListRow = {
  blocked_id: string
  created_at: string
  username: string | null
  name: string | null
  avatar_url: string | null
}

export async function fetchBlockedAccountsList(
  client: SupabaseClient = supabase
): Promise<
  | { ok: true; rows: BlockedAccountListRow[] }
  | { ok: false; message: string }
> {
  const { data, error } = await client.rpc("list_blocked_accounts")
  if (error) {
    return { ok: false, message: error.message }
  }
  const rows = (data ?? []) as BlockedAccountListRow[]
  return { ok: true, rows }
}

export async function fetchMyContentReports(
  userId: string,
  client: SupabaseClient = supabase
): Promise<
  | { ok: true; rows: ContentReportRow[] }
  | { ok: false; message: string }
> {
  const id = String(userId ?? "").trim()
  if (!id) {
    return { ok: false, message: "Sign in to view reports." }
  }
  const { data, error } = await client
    .from("content_reports")
    .select(
      "id, reporter_user_id, target_type, target_id, reported_user_id, reason, details, status, created_at, reviewed_at, reviewed_by"
    )
    .eq("reporter_user_id", id)
    .order("created_at", { ascending: false })
    .limit(100)
  if (error) {
    return { ok: false, message: error.message }
  }
  return { ok: true, rows: (data ?? []) as ContentReportRow[] }
}

export async function persistProfileIsPrivate(
  userId: string,
  isPrivate: boolean,
  client: SupabaseClient = supabase
): Promise<{ ok: true } | { ok: false; message: string }> {
  const { error } = await client
    .from("profiles")
    .update({ is_private: isPrivate })
    .eq("id", userId)
  if (error) {
    return { ok: false, message: error.message }
  }
  return { ok: true }
}

export type MutedDmPeerListRow = {
  conversation_id: string
  peer_id: string
  username: string | null
  name: string | null
  avatar_url: string | null
}

/** 1:1 DM peers with conversation notifications muted (not account-wide mute). */
export async function fetchMutedDmPeersList(
  client: SupabaseClient = supabase
): Promise<
  | { ok: true; rows: MutedDmPeerListRow[] }
  | { ok: false; message: string }
> {
  const { data, error } = await client.rpc("list_muted_dm_peers")
  if (error) {
    return { ok: false, message: error.message }
  }
  const rows = (data ?? []) as MutedDmPeerListRow[]
  return { ok: true, rows }
}

export async function unmuteDmPeerConversation(
  userId: string,
  conversationId: string,
  client: SupabaseClient = supabase
): Promise<{ ok: true } | { ok: false; message: string }> {
  return setConversationNotificationsEnabled(userId, conversationId, true, client)
}
