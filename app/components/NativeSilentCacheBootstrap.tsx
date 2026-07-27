"use client"

import { useEffect, useRef } from "react"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { hydrateNativeSilentCaches } from "@/lib/nativeSilentCacheBridge"
import { seedTradesCache, seedAccountsCache } from "@/lib/appDataCache"
import { seedFeedSession } from "@/lib/feedSessionCache"
import { seedExploreSession } from "@/lib/exploreSessionCache"
import { seedMessagesInboxSession } from "@/lib/messagesInboxSessionCache"
import { seedConversationSession } from "@/lib/conversationSessionCache"
import { seedRoomSession } from "@/lib/roomSessionCache"
import { seedProfileSession } from "@/lib/profileSessionCache"
import { seedTradeDetail } from "@/lib/tradeDetailCache"
import { seedNotificationsSession } from "@/lib/notificationsSessionCache"
import { seedLeaderboardSession } from "@/lib/leaderboardSessionCache"

/**
 * Native iOS: hydrate IndexedDB snapshots into memory caches on auth ready
 * so screens can paint instantly, then refresh in the background.
 */
export default function NativeSilentCacheBootstrap() {
  const enabled = useIsNativeIos()
  const { user, loading } = useUserProfile()
  const hydratedForRef = useRef<string | null>(null)

  useEffect(() => {
    if (!enabled || loading) return
    const userId = user?.id ? String(user.id) : ""
    if (!userId) {
      hydratedForRef.current = null
      return
    }
    if (hydratedForRef.current === userId) return
    hydratedForRef.current = userId

    void hydrateNativeSilentCaches(userId, {
      dashboardTrades: (uid, trades, fetchedAt) => {
        seedTradesCache(uid, trades as any[], fetchedAt)
      },
      dashboardAccounts: (uid, accounts, fetchedAt) => {
        seedAccountsCache(uid, accounts as any[], fetchedAt)
      },
      feed: (sessionKey, snapshot) => {
        seedFeedSession(sessionKey, snapshot as any)
      },
      explore: (snapshot) => {
        seedExploreSession(snapshot as any)
      },
      messagesInbox: (uid, conversations, fetchedAt) => {
        seedMessagesInboxSession(uid, conversations as any[], fetchedAt)
      },
      conversation: (uid, conversationId, snapshot) => {
        seedConversationSession(uid, conversationId, snapshot as any)
      },
      rooms: (snapshot) => {
        seedRoomSession(snapshot as any)
      },
      profile: (urlSegment, snapshot) => {
        seedProfileSession(urlSegment, snapshot as any)
      },
      tradeDetail: (tradeId, snapshot) => {
        seedTradeDetail(tradeId, snapshot as any)
      },
      notifications: (uid, payload, fetchedAt) => {
        seedNotificationsSession(uid, payload as any, fetchedAt)
      },
      leaderboard: (uid, payload, fetchedAt) => {
        seedLeaderboardSession(uid, payload as any, fetchedAt)
      },
    })
  }, [enabled, user?.id, loading])

  return null
}
