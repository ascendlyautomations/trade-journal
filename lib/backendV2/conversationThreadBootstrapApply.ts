import type { DmBlockStatus } from "../conversationBlocks.ts"
import { mergeMessageLists } from "../conversationMessageUtils.ts"
import type { ConversationThreadBootstrapV1 } from "./conversationThreadContracts.ts"
import { mapThreadBootstrapMessagesToWire } from "./conversationThreadContracts.ts"
import { commitThreadMarkRead } from "./conversationThreadReadLifecycle.ts"
import { patchMessagingInboxAfterThreadRead } from "./messagingInboxLocalPatch.ts"

export type ConversationThreadApplyTarget = {
  setConversation: (value: unknown) => void
  setParticipants: (value: unknown[]) => void
  setOtherUser: (value: unknown) => void
  setNotificationsEnabled: (enabled: boolean) => void
  setDmBlockStatus: (status: DmBlockStatus | null) => void
  setBlockStatusLoading: (loading: boolean) => void
  setMessages: (messages: unknown[]) => void
  setHasOlderMessages: (has: boolean) => void
  setMessagesLoaded: (loaded: boolean) => void
  setMessagesLoadError: (error: string | null) => void
  conversationMetaRef: {
    current: {
      conversation: unknown
      participants: unknown[]
      otherUser: unknown
    } | null
  }
  patchConversationSession: (
    userId: string,
    conversationId: string,
    patch: Record<string, unknown>
  ) => void
  urlSegment: string
}

export type ConversationThreadApplyOptions = {
  appendMessages?: boolean
  existingMessages?: unknown[]
  /** Cached paint before intentional bootstrap — no read side effects. */
  skipReadSideEffects?: boolean
  previousConversationUnread?: number
  openId?: number
}

export function applyConversationThreadBootstrap(
  bootstrap: ConversationThreadBootstrapV1,
  userId: string,
  conversationId: string,
  target: ConversationThreadApplyTarget,
  options?: ConversationThreadApplyOptions
): void {
  const { conversation, participants, notifications_enabled, block_status } =
    bootstrap.data

  target.setConversation(conversation)
  target.setParticipants(participants)
  target.setNotificationsEnabled(notifications_enabled)

  const other = participants.find((p) => p.user_id !== userId)
  const otherUser = other?.profiles
    ? {
        id: other.profiles.id,
        username: other.profiles.username,
        avatar_url: other.profiles.avatar_url,
      }
    : null
  target.setOtherUser(otherUser)

  if (block_status) {
    target.setDmBlockStatus({
      otherUserId: block_status.other_user_id,
      blockedByMe: block_status.blocked_by_me,
      blockedByOther: block_status.blocked_by_other,
    })
    target.setBlockStatusLoading(false)
  } else if (conversation.is_group) {
    target.setDmBlockStatus(null)
    target.setBlockStatusLoading(false)
  }

  target.conversationMetaRef.current = {
    conversation,
    participants,
    otherUser,
  }

  const wireMessages = mapThreadBootstrapMessagesToWire(bootstrap.data.messages)
  let merged = wireMessages
  if (options?.appendMessages && options.existingMessages?.length) {
    merged = mergeMessageLists(wireMessages, options.existingMessages)
  } else if (options?.existingMessages?.length) {
    merged = mergeMessageLists(wireMessages, options.existingMessages)
  }

  target.setMessages(merged)
  target.setHasOlderMessages(bootstrap.data.has_more_messages)
  target.setMessagesLoaded(true)
  target.setMessagesLoadError(null)

  target.patchConversationSession(userId, conversationId, {
    urlSegment: target.urlSegment,
    conversation,
    participants,
    otherUser,
    messages: merged,
    messagesLoaded: true,
    hasOlderMessages: bootstrap.data.has_more_messages,
    unreadCount: bootstrap.data.unread_count,
  })

  if (options?.skipReadSideEffects) return
  if (!bootstrap.data.mark_read.applied) return

  if (options?.openId != null) {
    commitThreadMarkRead(userId, conversationId, options.openId)
  }

  patchMessagingInboxAfterThreadRead({
    userId,
    conversationId,
    previousConversationUnread: options?.previousConversationUnread ?? 0,
    notificationsMarkedRead: bootstrap.data.notifications_marked_read,
  })
}
