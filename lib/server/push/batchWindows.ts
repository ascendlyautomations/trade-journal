import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

/** DM unread coalescing windows stay open until the conversation is read. */
export const DM_PUSH_BATCH_TTL_MS = 7 * 24 * 60 * 60 * 1000

/** Stable APNs thread-id / collapse-id for one DM conversation. */
export function dmPushThreadId(conversationId: string): string {
  return `dm:${conversationId}`
}

/**
 * Atomically increment the per-conversation DM push count for one recipient.
 * Returns the updated meta (including `count`), or null on failure.
 *
 * Delivery itself is immediate; this only tracks unread count for collapse-id
 * updates until the conversation is marked read.
 */
export async function bumpDmPushBatch(params: {
  recipientUserId: string
  conversationId: string
  meta: Record<string, unknown>
  windowEndsAt: Date
}): Promise<{ count: number; meta: Record<string, unknown> } | null> {
  const { data, error } = await supabaseServiceRole.rpc("bump_dm_push_batch", {
    p_recipient_user_id: params.recipientUserId,
    p_conversation_id: params.conversationId,
    p_meta: params.meta,
    p_window_ends_at: params.windowEndsAt.toISOString(),
  })

  if (error) {
    console.error("[push-batch] bumpDmPushBatch failed", error)
    return null
  }

  const meta =
    data && typeof data === "object" && !Array.isArray(data)
      ? (data as Record<string, unknown>)
      : {}
  const raw = meta.count
  const count =
    typeof raw === "number"
      ? raw
      : typeof raw === "string"
        ? Number.parseInt(raw, 10)
        : 1
  return {
    count: Number.isFinite(count) && count > 0 ? count : 1,
    meta,
  }
}

/** Clear DM coalescing state when a conversation is marked read. */
export async function deleteBatch(
  recipientUserId: string,
  batchKind: "dm",
  batchKey: string
): Promise<void> {
  const { error } = await supabaseServiceRole
    .from("push_batch_windows")
    .delete()
    .eq("recipient_user_id", recipientUserId)
    .eq("batch_kind", batchKind)
    .eq("batch_key", batchKey)

  if (error) {
    console.error("[push-batch] delete failed", error)
  }
}
