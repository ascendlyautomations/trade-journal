import {
  deliverMessagingPush,
  type MessagingPushPreferenceKey,
} from "@/lib/server/push/messagingPush"

export type ScheduleDmConversationPushParams = {
  recipientUserId: string
  conversationId: string
  messageId: string
  senderId: string
  preview: string
  isGroup: boolean
  groupName: string | null
  preferenceKey?: MessagingPushPreferenceKey
}

/** Stable APNs thread-id for one DM conversation (Notification Center grouping). */
export function dmPushThreadId(conversationId: string): string {
  return `dm:${conversationId}`
}

/**
 * Immediate per-message DM push.
 *
 * Same conversation → shared APS thread-id so alerts group in Notification Center.
 * No apns-collapse-id — each message stacks as its own notification (Trade Room style).
 *
 * No custom batching, no push_batch_windows, no aggregated "N new messages" copy.
 */
export async function scheduleDmConversationPush(
  params: ScheduleDmConversationPushParams
): Promise<void> {
  const recipientUserId = params.recipientUserId.trim()
  const conversationId = params.conversationId.trim()
  if (!recipientUserId || !conversationId) return

  const threadId = dmPushThreadId(conversationId)

  const content = JSON.stringify({
    conversation_id: conversationId,
    message_id: params.messageId,
    message_preview: params.preview,
    is_group: params.isGroup,
    group_name: params.isGroup ? params.groupName || "Group" : null,
    thread_id: threadId,
  })

  // Await delivery — callers must keep the invocation alive (e.g. next/server
  // `after()`). Never void-fire-and-forget: Vercel freezes suspended promises.
  await deliverMessagingPush({
    recipientUserId,
    kind: "message",
    sender_id: params.senderId,
    content,
    preferenceKey: params.preferenceKey ?? "direct_messages_enabled",
    prefsAlreadyChecked: true,
  })
}
