/**
 * Bridge: persist / hydrate existing session caches via IndexedDB on native iOS.
 */

import { isNativeIos } from "@/lib/nativePlatform"
import {
  NATIVE_CACHE_NS,
  NATIVE_CACHE_SOFT_TTL_MS,
  NATIVE_CONVERSATION_PERSIST_MAX,
  NATIVE_MESSAGES_PERSIST_MAX,
} from "@/lib/nativeCachePolicy"
import {
  durableCacheClearAll,
  durableCacheDeleteUser,
  durableCacheGetAllForUser,
  durableCacheSet,
  type DurableCacheEntry,
} from "@/lib/nativeDurableCache"

function nativeOnly(): boolean {
  return typeof window !== "undefined" && isNativeIos()
}

function capMessages<T extends { id?: unknown }>(messages: T[]): T[] {
  if (messages.length <= NATIVE_MESSAGES_PERSIST_MAX) return messages
  return messages.slice(-NATIVE_MESSAGES_PERSIST_MAX)
}

export function scheduleNativePersist(
  write: () => Promise<void>
): void {
  if (!nativeOnly()) return
  void write().catch(() => {})
}

export function persistDashboardTrades(userId: string, trades: unknown[]) {
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.dashboardTrades,
      userId,
      value: { trades },
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.dashboard_trades,
    })
  )
}

export function persistDashboardAccounts(userId: string, accounts: unknown[]) {
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.dashboardAccounts,
      userId,
      value: { accounts },
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.dashboard_accounts,
    })
  )
}

export function persistFeedSession(sessionKey: string, snapshot: unknown) {
  const userId = sessionKey.split(":")[0] ?? ""
  if (!userId) return
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.feed,
      userId,
      entityKey: sessionKey,
      value: snapshot,
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.feed,
    })
  )
}

export function persistExploreSession(
  userId: string | null,
  snapshot: unknown
) {
  const uid = userId?.trim() || "__anonymous__"
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.explore,
      userId: uid,
      value: snapshot,
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.explore,
    })
  )
}

export function persistMessagesInbox(userId: string, conversations: unknown[]) {
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.messagesInbox,
      userId,
      value: { conversations },
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.messages_inbox,
    })
  )
}

export function persistConversationSession(
  userId: string,
  conversationId: string,
  snapshot: Record<string, unknown>
) {
  const capped = {
    ...snapshot,
    messages: Array.isArray(snapshot.messages)
      ? capMessages(snapshot.messages as { id?: unknown }[])
      : [],
  }
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.conversation,
      userId,
      entityKey: conversationId,
      value: capped,
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.conversation,
    })
  )
}

export function persistRoomSession(
  userId: string,
  snapshot: {
    rooms: unknown[]
    messagesByKey: Record<string, { pinned?: unknown[]; main?: unknown[] }>
    sectionsByRoom: Record<string, unknown>
    fetchedAt: number
  }
) {
  const messagesByKey: Record<string, unknown> = {}
  const keys = Object.keys(snapshot.messagesByKey).slice(0, 12)
  for (const key of keys) {
    const entry = snapshot.messagesByKey[key]
    messagesByKey[key] = {
      pinned: Array.isArray(entry?.pinned)
        ? capMessages(entry.pinned as { id?: unknown }[])
        : [],
      main: Array.isArray(entry?.main)
        ? capMessages(entry.main as { id?: unknown }[])
        : [],
      hasOlder: (entry as { hasOlder?: boolean })?.hasOlder,
    }
  }
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.rooms,
      userId,
      value: {
        userId,
        rooms: snapshot.rooms,
        messagesByKey,
        sectionsByRoom: snapshot.sectionsByRoom,
        fetchedAt: snapshot.fetchedAt,
      },
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.rooms,
    })
  )
}

export function persistProfileSession(urlSegment: string, snapshot: unknown) {
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.profile,
      userId: "_profile_",
      entityKey: urlSegment,
      value: snapshot,
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.profile,
    })
  )
}

export function persistTradeDetail(tradeId: string, snapshot: unknown) {
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.tradeDetail,
      userId: "_trade_",
      entityKey: tradeId,
      value: snapshot,
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.trade_detail,
    })
  )
}

export function persistNotifications(
  userId: string,
  payload: { notifications: unknown[]; senderProfiles?: unknown }
) {
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.notifications,
      userId,
      value: payload,
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.notifications,
    })
  )
}

export function persistLeaderboard(
  userId: string,
  payload: { trades: unknown[]; view?: string }
) {
  scheduleNativePersist(() =>
    durableCacheSet({
      namespace: NATIVE_CACHE_NS.leaderboard,
      userId,
      value: payload,
      softTtlMs: NATIVE_CACHE_SOFT_TTL_MS.leaderboard,
    })
  )
}

export async function clearNativeSilentCacheForUser(userId: string) {
  if (!nativeOnly()) return
  await durableCacheDeleteUser(userId)
  // Also clear shared profile/trade namespaces when signing out.
  await durableCacheDeleteUser("_profile_")
  await durableCacheDeleteUser("_trade_")
  await durableCacheDeleteUser("__anonymous__")
}

export async function clearAllNativeSilentCache() {
  if (!nativeOnly()) return
  await durableCacheClearAll()
}

type HydrateHandlers = {
  dashboardTrades?: (userId: string, trades: unknown[], fetchedAt: number) => void
  dashboardAccounts?: (
    userId: string,
    accounts: unknown[],
    fetchedAt: number
  ) => void
  feed?: (sessionKey: string, snapshot: unknown, fetchedAt: number) => void
  explore?: (snapshot: unknown, fetchedAt: number) => void
  messagesInbox?: (
    userId: string,
    conversations: unknown[],
    fetchedAt: number
  ) => void
  conversation?: (
    userId: string,
    conversationId: string,
    snapshot: unknown,
    fetchedAt: number
  ) => void
  rooms?: (snapshot: unknown, fetchedAt: number) => void
  profile?: (urlSegment: string, snapshot: unknown, fetchedAt: number) => void
  tradeDetail?: (tradeId: string, snapshot: unknown, fetchedAt: number) => void
  notifications?: (
    userId: string,
    payload: unknown,
    fetchedAt: number
  ) => void
  leaderboard?: (userId: string, payload: unknown, fetchedAt: number) => void
}

/**
 * Load IndexedDB snapshots into in-memory session caches for one user.
 * Conversation keys are capped to the most recently fetched N threads.
 */
export async function hydrateNativeSilentCaches(
  userId: string,
  handlers: HydrateHandlers
): Promise<void> {
  if (!nativeOnly()) return
  const uid = userId.trim()
  if (!uid) return

  const rows = await durableCacheGetAllForUser(uid)
  const anon = await durableCacheGetAllForUser("__anonymous__")
  const profiles = await durableCacheGetAllForUser("_profile_")
  const trades = await durableCacheGetAllForUser("_trade_")
  const all = [...rows, ...anon, ...profiles, ...trades]

  const conversations: DurableCacheEntry[] = []

  for (const row of all) {
    const ns = row.namespace
    const value = row.value as Record<string, unknown>
    if (ns === NATIVE_CACHE_NS.dashboardTrades && handlers.dashboardTrades) {
      const list = Array.isArray(value.trades) ? value.trades : []
      handlers.dashboardTrades(uid, list, row.fetchedAt)
    } else if (
      ns === NATIVE_CACHE_NS.dashboardAccounts &&
      handlers.dashboardAccounts
    ) {
      const list = Array.isArray(value.accounts) ? value.accounts : []
      handlers.dashboardAccounts(uid, list, row.fetchedAt)
    } else if (ns === NATIVE_CACHE_NS.feed && handlers.feed) {
      const entityKey = row.key.split(":").slice(2).join(":") || row.key
      handlers.feed(entityKey, row.value, row.fetchedAt)
    } else if (ns === NATIVE_CACHE_NS.explore && handlers.explore) {
      handlers.explore(row.value, row.fetchedAt)
    } else if (
      ns === NATIVE_CACHE_NS.messagesInbox &&
      handlers.messagesInbox
    ) {
      const list = Array.isArray(value.conversations)
        ? value.conversations
        : []
      handlers.messagesInbox(uid, list, row.fetchedAt)
    } else if (ns === NATIVE_CACHE_NS.conversation) {
      conversations.push(row)
    } else if (ns === NATIVE_CACHE_NS.rooms && handlers.rooms) {
      handlers.rooms(row.value, row.fetchedAt)
    } else if (ns === NATIVE_CACHE_NS.profile && handlers.profile) {
      const entityKey = row.key.split(":").slice(2).join(":") || ""
      if (entityKey) handlers.profile(entityKey, row.value, row.fetchedAt)
    } else if (ns === NATIVE_CACHE_NS.tradeDetail && handlers.tradeDetail) {
      const entityKey = row.key.split(":").slice(2).join(":") || ""
      if (entityKey) handlers.tradeDetail(entityKey, row.value, row.fetchedAt)
    } else if (
      ns === NATIVE_CACHE_NS.notifications &&
      handlers.notifications
    ) {
      handlers.notifications(uid, row.value, row.fetchedAt)
    } else if (ns === NATIVE_CACHE_NS.leaderboard && handlers.leaderboard) {
      handlers.leaderboard(uid, row.value, row.fetchedAt)
    }
  }

  if (handlers.conversation && conversations.length > 0) {
    conversations
      .sort((a, b) => b.fetchedAt - a.fetchedAt)
      .slice(0, NATIVE_CONVERSATION_PERSIST_MAX)
      .forEach((row) => {
        const conversationId = row.key.split(":").slice(2).join(":") || ""
        if (!conversationId) return
        handlers.conversation?.(uid, conversationId, row.value, row.fetchedAt)
      })
  }
}
