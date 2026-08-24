/**
 * Backend V2 repository adapter interfaces (Phase 1).
 *
 * Pattern (future cutover):
 *   Screen → BootstrapProviding
 *            ├─ *RestBootstrapRepository  (current REST fan-out)
 *            └─ *RpcBootstrapRepository   (rpc_v1_*_bootstrap)
 *
 * Phase 1: interfaces + unused stubs only. Existing repositories untouched.
 */

import type {
  ActivityBootstrapV1,
  CalendarBootstrapV1,
  DashboardBootstrapV1,
  ExploreBootstrapV1,
  FeedBootstrapV1,
  LeaderboardBootstrapV1,
  MessagesBootstrapV1,
  ProfileBootstrapV1,
  RoomsBootstrapV1,
  SessionBootstrapV1,
  SettingsBootstrapV1,
  TradeDetailBootstrapV1,
} from "./contracts.ts"

export type SessionBootstrapProviding = {
  loadSessionBootstrap(): Promise<SessionBootstrapV1>
}

export type DashboardBootstrapProviding = {
  loadDashboardBootstrap(input?: {
    accountId?: string | null
  }): Promise<DashboardBootstrapV1>
}

export type FeedBootstrapProviding = {
  loadFeedBootstrap(input: {
    scope: "following" | "global"
    contentFilter?:
      | "all"
      | "trades"
      | "reels"
      | "posts"
      | "achievements"
    cursor?: string | null
    limit?: number
  }): Promise<FeedBootstrapV1>
}

export type ProfileBootstrapProviding = {
  loadProfileBootstrap(input: {
    profileId?: string
    username?: string
  }): Promise<ProfileBootstrapV1>
}

export type MessagesBootstrapProviding = {
  loadMessagesBootstrap(input?: {
    cursor?: string | null
    limit?: number
  }): Promise<MessagesBootstrapV1>
}

export type RoomsBootstrapProviding = {
  loadRoomBootstrap(input: {
    roomId: string
    cursor?: string | null
  }): Promise<RoomsBootstrapV1>
}

export type ActivityBootstrapProviding = {
  loadActivityBootstrap(input?: {
    cursor?: string | null
    limit?: number
  }): Promise<ActivityBootstrapV1>
}

export type ExploreBootstrapProviding = {
  loadExploreBootstrap(): Promise<ExploreBootstrapV1>
}

export type LeaderboardBootstrapProviding = {
  loadLeaderboardBootstrap(input: {
    timeframe: string
    category: string
    cursor?: string | null
  }): Promise<LeaderboardBootstrapV1>
}

export type CalendarBootstrapProviding = {
  loadCalendarBootstrap(input: {
    year: number
    month: number
    accountId?: string | null
  }): Promise<CalendarBootstrapV1>
}

export type TradeDetailBootstrapProviding = {
  loadTradeDetailBootstrap(input: {
    tradeId: string
  }): Promise<TradeDetailBootstrapV1>
}

export type SettingsBootstrapProviding = {
  loadSettingsBootstrap(): Promise<SettingsBootstrapV1>
}

/**
 * Marker for dual-run adapters. Not registered in DI in Phase 1.
 */
export type BackendV2BootstrapAdapters = {
  session: SessionBootstrapProviding
  dashboard: DashboardBootstrapProviding
  feed: FeedBootstrapProviding
  profile: ProfileBootstrapProviding
  messages: MessagesBootstrapProviding
  rooms: RoomsBootstrapProviding
  activity: ActivityBootstrapProviding
  explore: ExploreBootstrapProviding
  leaderboard: LeaderboardBootstrapProviding
  calendar: CalendarBootstrapProviding
  tradeDetail: TradeDetailBootstrapProviding
  settings: SettingsBootstrapProviding
}

/** Stub used only to document the Rpc side — throws until Phase 2+. */
export function createUnimplementedRpcBootstrap<T extends object>(
  name: string
): T {
  return new Proxy(
    {},
    {
      get(_target, prop) {
        if (prop === "then") return undefined
        return async () => {
          throw new Error(
            `Backend V2 RPC adapter "${name}.${String(prop)}" is not implemented yet (Phase 1 infrastructure only)`
          )
        }
      },
    }
  ) as T
}
