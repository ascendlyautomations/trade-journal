import {
  bumpDmPushBatch,
  DM_PUSH_BATCH_TTL_MS,
  dmPushThreadId,
} from "@/lib/server/push/batchWindows"
import { scheduleMessagingPush } from "@/lib/server/push/messagingPush"

export type ScheduleDmConversationPushParams = {
  recipientUserId: string
  conversationId: string
  messageId: string
  senderId: string
  preview: string
  isGroup: boolean
  groupName: string | null
}

/**
 * Per-conversation DM push coalescing.
 *
 * Same conversation → one evolving APNs alert (collapse-id + thread-id).
 * Different conversations → separate alerts / threads.
 *
 * Delivery is immediate on each message (most reliable update path on iOS);
 * the batch row only tracks the unread count until the conversation is opened.
 */
export async function scheduleDmConversationPush(
  params: ScheduleDmConversationPushParams
): Promise<void> {
  const recipientUserId = params.recipientUserId.trim()
  const conversationId = params.conversationId.trim()
  if (!recipientUserId || !conversationId) return

  const bumped = await bumpDmPushBatch({
    recipientUserId,
    conversationId,
    windowEndsAt: new Date(Date.now() + DM_PUSH_BATCH_TTL_MS),
    meta: {
      last_message_id: params.messageId,
      last_preview: params.preview,
      is_group: params.isGroup,
      group_name: params.isGroup ? params.groupName || "Group" : null,
      sender_id: params.senderId,
    },
  })

  // If the RPC is unavailable (migration not applied), fall back to a single
  // unbatched push so messaging still notifies — never block delivery.
  const batchCount = bumped?.count ?? 1
  const threadId = dmPushThreadId(conversationId)

  const content = JSON.stringify({
    conversation_id: conversationId,
    message_id: params.messageId,
    message_preview: params.preview,
    is_group: params.isGroup,
    group_name: params.isGroup ? params.groupName || "Group" : null,
    batch_count: batchCount,
    thread_id: threadId,
    collapse_id: threadId,
  })

  scheduleMessagingPush({
    recipientUserId,
    kind: "message",
    sender_id: params.senderId,
    content,
    prefsAlreadyChecked: true,
  })
}
