import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "./supabaseClient"

/** True when userId is a row in conversation_participants for conversationId. */
export async function isConversationParticipant(
  conversationId: string,
  userId: string,
  client: SupabaseClient = supabase
): Promise<boolean> {
  if (!conversationId || !userId) return false

  const { data, error } = await client
    .from("conversation_participants")
    .select("id")
    .eq("conversation_id", conversationId)
    .eq("user_id", userId)
    .maybeSingle()

  if (error) return false
  return data != null
}
