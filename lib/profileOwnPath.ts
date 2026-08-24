import type { SessionProfileV1 } from "./backendV2/contracts.ts"
import { readDashboardBootstrapCache } from "./backendV2/dashboardBootstrapCache.ts"
import { readSessionBootstrapCache } from "./backendV2/sessionBootstrapCache.ts"
import { getCachedTrades } from "./appDataCache.ts"
import { normalizeProfileUsername } from "./profileUsername.ts"
import {
  PUBLIC_TRADE_SELECT,
  sanitizeTradesForViewer,
} from "./publicAccountPrivacy.ts"

/** Public profile columns loaded by Profile page — must stay in sync with page.tsx. */
export const PUBLIC_PROFILE_HEADER_FIELDS = [
  "id",
  "username",
  "name",
  "bio",
  "avatar_url",
  "trading_style",
  "trader_type",
  "primary_market",
  "started_trading",
  "is_private",
  "created_at",
] as const

export type PublicProfileHeader = {
  id: string
  username: string | null
  name?: string | null
  bio: string | null
  avatar_url: string | null
  trading_style: string | null
  trader_type: string | null
  primary_market: string | null
  started_trading: string | null
  is_private: boolean | null
  created_at: string | null
}

export function sessionProfileToPublicHeader(
  session: SessionProfileV1
): PublicProfileHeader {
  return {
    id: session.id,
    username: session.username,
    name: null,
    bio: session.bio,
    avatar_url: session.avatar_url,
    trading_style: session.trading_style,
    trader_type: session.trader_type,
    primary_market: session.primary_market,
    started_trading: session.started_trading,
    is_private: session.is_private,
    created_at: null,
  }
}

export function resolveOwnProfileHeaderFromSession(
  viewerUserId: string | null | undefined,
  urlSegment: string
): PublicProfileHeader | null {
  if (!viewerUserId) return null
  const boot = readSessionBootstrapCache(viewerUserId)
  if (!boot?.data.session_profile) return null
  const session = boot.data.session_profile
  if (String(session.id) !== String(viewerUserId)) return null

  const segment = urlSegment.trim()
  const byId = segment.toLowerCase() === String(viewerUserId).toLowerCase()
  const byUsername =
    session.username != null &&
    normalizeProfileUsername(segment) ===
      normalizeProfileUsername(String(session.username))

  if (!byId && !byUsername) return null
  return sessionProfileToPublicHeader(session)
}

export type DashboardTradeCacheCompleteness = {
  /** True when dashboard trade_window_meta.history_complete is true. */
  historyComplete: boolean
  totalTradeCount: number
}

export function readDashboardPublicTradeCompleteness(
  userId: string
): DashboardTradeCacheCompleteness | null {
  const boot = readDashboardBootstrapCache(userId)
  if (!boot) return null
  return {
    historyComplete: boot.data.trade_window_meta.history_complete === true,
    totalTradeCount: boot.data.trade_window_meta.total_trade_count ?? 0,
  }
}

/** Public trades from warmed app cache — owner sees sanitized owner rows. */
export function resolveOwnPublicTradesFromCache(userId: string) {
  const cached = getCachedTrades(userId)
  if (!cached?.length) return null
  const publicRows = cached.filter((t) => t?.is_public === true)
  return sanitizeTradesForViewer(publicRows, { isOwner: true })
}

/** Lightweight summary rows from complete dashboard public-trade cache. */
export function resolveOwnSummaryTradesFromCache(userId: string) {
  const rows = resolveOwnPublicTradesFromCache(userId)
  if (!rows) return null
  return rows.map((t) => ({
    id: t.id,
    created_at: t.created_at,
    pnl: t.pnl,
    rr: t.rr,
    mode: t.mode,
    account_type: t.account_type,
  }))
}

export const PROFILE_TRADE_CARD_SELECT = PUBLIC_TRADE_SELECT
