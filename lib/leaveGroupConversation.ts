import type { SupabaseClient } from "@supabase/supabase-js"

export type LeaveGroupConversationStatus = "left" | "already_left"

/** Server-owned group leave (membership + system line, idempotent). */
export async function leaveGroupConversation(
  supabase: SupabaseClient,
  conversationId: string
): Promise<{ status: LeaveGroupConversationStatus; error: Error | null }> {
  const { data, error } = await supabase.rpc("rpc_v1_leave_group_conversation", {
    p_conversation_id: conversationId,
  })

  if (error) {
    return { status: "already_left", error }
  }

  const status = (data as { status?: string } | null)?.status
  if (status === "left" || status === "already_left") {
    return { status, error: null }
  }

  return {
    status: "already_left",
    error: new Error("Unexpected leave group response"),
  }
}