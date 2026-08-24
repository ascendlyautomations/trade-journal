/**
 * Local inbox + aggregate unread patches after thread bootstrap mark-read.
 * Avoids refetching hidden IDs, participant lists, muted prefs, or unread RPCs.
 */

import {
  messagingBootstrapCacheKey,
  readMessagingBootstrapCache,
  writeMessagingBootstrapCache,
} from "./messagingBootstrapCache.ts"
import { patchSessionBadges } from "./sessionBootstrapCache.ts"

export const MESSAGING_INBOX_CONVERSATION_UNREAD_PATCH =
  "tj-messaging-inbox-conversation-unread-patch"

export const MESSAGING_DM_UNREAD_LOCAL_PATCH =
  "tj-messaging-dm-unread-local-patch"

export type MessagingInboxUnreadPatchDetail = {
  userId: string
  conversationId: string
  unreadCount: number
  dmUnreadTotal: number
}

function patchInboxSessionConversations(
  userId: string,
  conversationId: string,
  unreadCount: number
): void {
  if (typeof window === "undefined") return
  try {
    const { readMessagesInboxSession, writeMessagesInboxSession } =
      require("../messagesInboxSessionCache.ts") as {
        readMessagesInboxSession: (id: string) => {
          conversations: Array<{ id: string; unreadCount?: number }>
        } | null
        writeMessagesInboxSession: (
          id: string,
          conversations: unknown[]
        ) => void
      }
    const session = readMessagesInboxSession(userId)
    if (!session?.conversations?.length) return
    const next = session.conversations.map((row) =>
      String(row.id) === conversationId
        ? { ...row, unreadCount: unreadCount }
        : row
    )
    writeMessagesInboxSession(userId, next)
  } catch {
    /* session cache optional in tests */
  }
}

export function patchMessagingInboxAfterThreadRead(input: {
  userId: string
  conversationId: string
  /** Unread count removed from aggregate (clamped internally). */
  previousConversationUnread: number
  notificationsMarkedRead?: number
}): MessagingInboxUnreadPatchDetail {
  const userId = input.userId.trim()
  const conversationId = input.conversationId.trim()
  const removed = Math.max(0, Math.floor(input.previousConversationUnread))

  const cacheKey = messagingBootstrapCacheKey({ userId })
  const cached = readMessagingBootstrapCache(cacheKey)

  let dmUnreadTotal = cached?.data.dm_unread_total ?? 0
  if (cached) {
    const prevConversationUnread =
      cached.data.conversations.find((c) => c.id === conversationId)
        ?.unread_count ?? removed
    const delta = Math.max(0, prevConversationUnread)
    dmUnreadTotal = Math.max(0, dmUnreadTotal - delta)

    const conversations = cached.data.conversations.map((c) =>
      c.id === conversationId ? { ...c, unread_count: 0 } : c
    )

    writeMessagingBootstrapCache(
      cacheKey,
      userId,
      {
        ...cached,
        data: {
          ...cached.data,
          conversations,
          dm_unread_total: dmUnreadTotal,
        },
      },
      "cache"
    )
  } else if (removed > 0) {
    dmUnreadTotal = Math.max(0, dmUnreadTotal - removed)
  }

  patchSessionBadges(userId, { dm_unread: dmUnreadTotal })
  patchInboxSessionConversations(userId, conversationId, 0)

  const detail: MessagingInboxUnreadPatchDetail = {
    userId,
    conversationId,
    unreadCount: 0,
    dmUnreadTotal,
  }

  if (typeof window !== "undefined") {
    window.dispatchEvent(
      new CustomEvent(MESSAGING_INBOX_CONVERSATION_UNREAD_PATCH, { detail })
    )
    window.dispatchEvent(
      new CustomEvent(MESSAGING_DM_UNREAD_LOCAL_PATCH, {
        detail: { userId, dmUnread: dmUnreadTotal },
      })
    )
  }

  if ((input.notificationsMarkedRead ?? 0) > 0 && typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  }

  return detail
}
