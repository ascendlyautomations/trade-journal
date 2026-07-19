import type { ReplyTarget } from "./replyReference"
import { computeNewestMessage } from "./conversationMessageUtils"
import {
  CONVERSATION_LRU_MAX_SIZE,
  ConversationLruStore,
} from "./conversationLruStore"

export { CONVERSATION_LRU_MAX_SIZE }

export type ConversationSessionSnapshot = {
  conversationId: string
  urlSegment: string
  messages: any[]
  messagesLoaded: boolean
  hasOlderMessages?: boolean
  conversation: any | null
  participants: any[]
  otherUser: any | null
  newestMessageId: string | null
  newestTimestamp: string | null
  unreadCount: number
  scrollTop: number
  wasAtBottom: boolean
  draft: string
  replyTarget: ReplyTarget | null
  tradesById: Record<string, any>
  postsById: Record<string, any>
  lastAccessedAt: number
  fetchedAt: number
}

type ConversationSessionWrite = Omit<
  ConversationSessionSnapshot,
  "conversationId" | "lastAccessedAt" | "fetchedAt"
>

const store = new ConversationLruStore<ConversationSessionSnapshot>()

export function conversationSessionKey(
  userId: string,
  conversationId: string
): string {
  return `${userId}:${conversationId}`
}

/** Pin the open conversation so LRU eviction never drops it while the user is viewing it. */
export function setActiveConversationSession(
  userId: string | null,
  conversationId: string | null
) {
  store.setPinned(
    userId && conversationId
      ? conversationSessionKey(userId, conversationId)
      : null
  )
}

/** Promote a conversation to most-recently-used without mutating its snapshot. */
export function touchConversationSession(
  userId: string,
  conversationId: string
): boolean {
  return store.touch(conversationSessionKey(userId, conversationId))
}

export function peekConversationSession(
  userId: string,
  conversationId: string
): ConversationSessionSnapshot | null {
  return store.peek(conversationSessionKey(userId, conversationId))
}

export function readConversationSession(
  userId: string,
  conversationId: string
): ConversationSessionSnapshot | null {
  return store.get(conversationSessionKey(userId, conversationId))
}

export function findConversationSessionByUrlSegment(
  userId: string,
  urlSegment: string
): ConversationSessionSnapshot | null {
  const segment = urlSegment.trim().toLowerCase()
  if (!segment || !userId) return null
  const entry = store.findEntryForKeyPrefix(
    `${userId}:`,
    (session) => session.urlSegment.trim().toLowerCase() === segment
  )
  if (!entry) return null
  return store.get(conversationSessionKey(userId, entry.conversationId))
}

export function writeConversationSession(
  userId: string,
  conversationId: string,
  snapshot: ConversationSessionWrite
) {
  const key = conversationSessionKey(userId, conversationId)
  const now = Date.now()
  store.set(key, {
    ...snapshot,
    conversationId,
    unreadCount: snapshot.unreadCount ?? 0,
    tradesById: snapshot.tradesById ?? {},
    postsById: snapshot.postsById ?? {},
    lastAccessedAt: now,
    fetchedAt: now,
  })
}

export function patchConversationSession(
  userId: string,
  conversationId: string,
  patch: Partial<ConversationSessionWrite>
): ConversationSessionSnapshot | null {
  return store.patch(conversationSessionKey(userId, conversationId), patch)
}

export function updateConversationMessages(
  userId: string,
  conversationId: string,
  updater: (messages: any[]) => any[],
  meta?: Partial<ConversationSessionWrite>
): ConversationSessionSnapshot | null {
  const key = conversationSessionKey(userId, conversationId)
  const prev = store.peek(key)
  const messages = updater(prev?.messages ?? [])
  const newest = computeNewestMessage(messages)

  if (prev) {
    return store.patch(key, {
      messages,
      newestMessageId: newest.id,
      newestTimestamp: newest.timestamp,
      messagesLoaded: true,
    })
  }

  const now = Date.now()
  store.set(key, {
    urlSegment: meta?.urlSegment ?? "",
    messages,
    messagesLoaded: true,
    hasOlderMessages: meta?.hasOlderMessages ?? false,
    conversation: meta?.conversation ?? null,
    participants: meta?.participants ?? [],
    otherUser: meta?.otherUser ?? null,
    newestMessageId: newest.id,
    newestTimestamp: newest.timestamp,
    unreadCount: meta?.unreadCount ?? 0,
    scrollTop: meta?.scrollTop ?? 0,
    wasAtBottom: meta?.wasAtBottom ?? true,
    draft: meta?.draft ?? "",
    replyTarget: meta?.replyTarget ?? null,
    tradesById: meta?.tradesById ?? {},
    postsById: meta?.postsById ?? {},
    conversationId,
    lastAccessedAt: now,
    fetchedAt: now,
  })
  return store.peek(key)
}

export function invalidateConversationSession(
  userId: string,
  conversationId: string
) {
  store.delete(conversationSessionKey(userId, conversationId))
}

export function clearConversationSessionsForUser(userId: string) {
  store.deleteByPrefix(`${userId}:`)
}

/** @internal Test helper */
export function resetConversationSessionCacheForTests() {
  store.clear()
}

/** @internal Test helper */
export function getConversationSessionCacheSize(): number {
  return store.size()
}

/** @internal Test helper */
export function getOldestConversationSessionCacheKey(): string | null {
  return store.oldestKey()
}
