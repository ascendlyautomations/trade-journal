import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "@/lib/supabaseClient"
import { isDemoUserId } from "@/lib/demo/constants"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"

/** In-memory mute overrides for demo mode (session-local). */
const demoMutedByUser = new Map<string, Set<string>>()

function demoMutedSet(userId: string): Set<string> {
  let set = demoMutedByUser.get(userId)
  if (!set) {
    set = new Set()
    demoMutedByUser.set(userId, set)
  }
  return set
}

export async function fetchConversationNotificationsEnabled(
  userId: string,
  conversationId: string,
  client: SupabaseClient = supabase
): Promise<boolean> {
  if (!userId || !conversationId) return true

  if (isDemoSupabaseBlocked() && isDemoUserId(userId)) {
    return !demoMutedSet(userId).has(conversationId)
  }

  const { data, error } = await client
    .from("conversation_member_preferences")
    .select("notifications_enabled")
    .eq("user_id", userId)
    .eq("conversation_id", conversationId)
    .maybeSingle()

  if (error) {
    console.error("[conversationMemberPreferences] fetch:", error)
    return true
  }

  if (!data) return true
  return data.notifications_enabled !== false
}

/** Conversation ids the user has muted (notifications_enabled = false). */
export async function fetchMutedConversationIds(
  userId: string,
  conversationIds?: string[],
  client: SupabaseClient = supabase
): Promise<Set<string>> {
  const muted = new Set<string>()
  if (!userId) return muted

  if (isDemoSupabaseBlocked() && isDemoUserId(userId)) {
    const all = demoMutedSet(userId)
    if (!conversationIds?.length) return new Set(all)
    for (const id of conversationIds) {
      if (all.has(id)) muted.add(id)
    }
    return muted
  }

  let query = client
    .from("conversation_member_preferences")
    .select("conversation_id")
    .eq("user_id", userId)
    .eq("notifications_enabled", false)

  if (conversationIds?.length) {
    query = query.in("conversation_id", conversationIds)
  }

  const { data, error } = await query
  if (error) {
    console.error("[conversationMemberPreferences] muted ids:", error)
    return muted
  }

  for (const row of data || []) {
    const id = String(row.conversation_id ?? "").trim()
    if (id) muted.add(id)
  }
  return muted
}

export async function setConversationNotificationsEnabled(
  userId: string,
  conversationId: string,
  enabled: boolean,
  client: SupabaseClient = supabase
): Promise<{ ok: true } | { ok: false; message: string }> {
  if (!userId || !conversationId) {
    return { ok: false, message: "Missing conversation." }
  }

  if (isDemoSupabaseBlocked() && isDemoUserId(userId)) {
    const set = demoMutedSet(userId)
    if (enabled) set.delete(conversationId)
    else set.add(conversationId)
    return { ok: true }
  }

  const { error } = await client.from("conversation_member_preferences").upsert(
    {
      user_id: userId,
      conversation_id: conversationId,
      notifications_enabled: enabled,
    },
    { onConflict: "user_id,conversation_id" }
  )

  if (error) {
    console.error("[conversationMemberPreferences] upsert:", error)
    return {
      ok: false,
      message: "Could not update notification settings. Try again.",
    }
  }

  return { ok: true }
}
