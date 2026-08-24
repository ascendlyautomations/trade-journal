/**
 * Seed thread header from inbox V2 bootstrap cache before canonical thread load.
 */

import type { MessagingConversationV1 } from "./contracts.ts"
import {
  messagingBootstrapCacheKey,
  readMessagingBootstrapCache,
} from "./messagingBootstrapCache.ts"
import { normalizeProfileUsername } from "../profileUsername.ts"
import {
  registerConversationThreadAlias,
  resolveConversationThreadAlias,
} from "./conversationThreadAliasCache.ts"

export {
  registerConversationThreadAlias,
  resolveConversationThreadAlias,
  clearConversationThreadAliases,
} from "./conversationThreadAliasCache.ts"

export type ConversationThreadHeaderSeed = {
  conversationId: string
  conversation: {
    id: string
    is_group: boolean
    name: string | null
    avatar_url: string | null
    is_pinned: boolean
  }
  participants: Array<{
    user_id: string
    profiles: {
      id: string
      username: string | null
      avatar_url: string | null
    } | null
  }>
  otherUser: {
    id: string
    username: string | null
    avatar_url: string | null
  } | null
  notificationsEnabled: boolean
  unreadCount: number
}

function mapConversationToSeed(
  row: MessagingConversationV1,
  viewerId: string
): ConversationThreadHeaderSeed {
  const participants = row.participants.map((p) => ({
    user_id: p.user_id,
    profiles: {
      id: p.user_id,
      username: p.username,
      avatar_url: p.avatar_url,
    },
  }))
  const other = participants.find((p) => p.user_id !== viewerId)
  return {
    conversationId: row.id,
    conversation: {
      id: row.id,
      is_group: row.is_group,
      name: row.name,
      avatar_url: row.avatar_url,
      is_pinned: row.is_pinned,
    },
    participants,
    otherUser: other?.profiles
      ? {
          id: other.user_id,
          username: other.profiles.username,
          avatar_url: other.profiles.avatar_url,
        }
      : null,
    notificationsEnabled: !row.muted,
    unreadCount: row.unread_count,
  }
}

function findInConversations(
  conversations: MessagingConversationV1[],
  viewerId: string,
  opts: { conversationId?: string | null; urlSegment?: string | null }
): ConversationThreadHeaderSeed | null {
  const byId = opts.conversationId?.trim()
  if (byId) {
    const row = conversations.find((c) => c.id === byId)
    if (row) return mapConversationToSeed(row, viewerId)
  }
  const segment = normalizeProfileUsername(opts.urlSegment ?? "")
  if (segment) {
    for (const row of conversations) {
      const peer = row.participants.find((p) => p.user_id !== viewerId)
      const username = normalizeProfileUsername(peer?.username ?? "")
      if (username === segment) return mapConversationToSeed(row, viewerId)
    }
  }
  return null
}

function inboxConversationsFromSession(
  userId: string
): MessagingConversationV1[] | null {
  if (typeof window === "undefined") return null
  try {
    const { readMessagesInboxSession } = require("../messagesInboxSessionCache.ts") as {
      readMessagesInboxSession: (id: string) => { conversations?: unknown[] } | null
    }
    const session = readMessagesInboxSession(userId)
    if (!session?.conversations?.length) return null
    return session.conversations as MessagingConversationV1[]
  } catch {
    return null
  }
}

export function readConversationThreadHeaderSeed(input: {
  userId: string
  conversationId?: string | null
  urlSegment?: string | null
}): ConversationThreadHeaderSeed | null {
  const viewerId = input.userId.trim()
  if (!viewerId) return null

  let conversationId = input.conversationId?.trim() || null
  const segment = input.urlSegment?.trim() || null
  if (!conversationId && segment) {
    conversationId = resolveConversationThreadAlias(viewerId, segment)
  }

  const cacheKey = messagingBootstrapCacheKey({ userId: viewerId })
  const bootstrap = readMessagingBootstrapCache(cacheKey)
  if (bootstrap?.data.conversations?.length) {
    const seed = findInConversations(bootstrap.data.conversations, viewerId, {
      conversationId,
      urlSegment: segment,
    })
    if (seed) {
      if (segment) {
        registerConversationThreadAlias(viewerId, segment, seed.conversationId)
      }
      return seed
    }
  }

  const sessionRows = inboxConversationsFromSession(viewerId)
  if (sessionRows?.length) {
    const seed = findInConversations(sessionRows, viewerId, {
      conversationId,
      urlSegment: segment,
    })
    if (seed) {
      if (segment) {
        registerConversationThreadAlias(viewerId, segment, seed.conversationId)
      }
      return seed
    }
  }

  return null
}
