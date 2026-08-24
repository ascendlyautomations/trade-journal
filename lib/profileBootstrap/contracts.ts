import type { PublicProfileHeader } from "../profileOwnPath.ts"

export type ProfileBootstrapViewerV1 = {
  is_own_profile: boolean
  can_view_trades: boolean
  is_following: boolean
  is_requested: boolean
  follows_you: boolean
}

export type ProfileBootstrapPublicStatsV1 = {
  total_trades: number
  wins: number
  total_pnl: number
}

export type ProfileBootstrapTradeEngagementV1 = Record<
  string,
  {
    like_count: number
    liked_by_me: boolean
    comment_count: number
  }
>

export type ProfileBootstrapV1 = {
  meta: {
    contract_version: number
    found: boolean
    server_time?: string
  }
  data: {
    profile: PublicProfileHeader | null
    viewer: ProfileBootstrapViewerV1
    followers_count: number
    following_count: number
    section_counts: Record<string, unknown>
    public_stats: ProfileBootstrapPublicStatsV1 | null
    active_tab: string
    trades_page: {
      items: Record<string, unknown>[]
      page_meta: {
        limit: number
        returned: number
        has_more: boolean
        next_cursor: string | null
      }
    } | null
    trade_engagement: ProfileBootstrapTradeEngagementV1 | null
  }
}

export function decodeProfileBootstrapV1(raw: unknown): ProfileBootstrapV1 {
  if (!raw || typeof raw !== "object") {
    throw new Error("ProfileBootstrapV1: invalid payload")
  }
  const envelope = raw as ProfileBootstrapV1
  if (!envelope.meta || typeof envelope.meta !== "object") {
    throw new Error("ProfileBootstrapV1: missing meta")
  }
  if (!envelope.data || typeof envelope.data !== "object") {
    throw new Error("ProfileBootstrapV1: missing data")
  }
  if (!envelope.data.viewer || typeof envelope.data.viewer !== "object") {
    throw new Error("ProfileBootstrapV1: missing viewer")
  }
  return envelope
}
