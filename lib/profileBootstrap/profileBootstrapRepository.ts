import type { SupabaseClient } from "@supabase/supabase-js"
import { BackendV2RpcError } from "../backendV2/rpcClient.ts"
import { BackendV2RpcNames } from "../backendV2/versioning.ts"
import { sanitizeTradesForViewer } from "../publicAccountPrivacy.ts"
import {
  isTransientPostgrestError,
  withTransientPostgrestRetry,
} from "../postgrestTransientRetry.ts"
import { writeTradeSocial } from "../tradeSocialCache.ts"
import {
  clearProfileBootstrapRpcUnavailableCache,
  isProfileBootstrapRpcCachedUnavailable,
  markProfileBootstrapRpcUnavailable,
} from "./profileV1Availability.ts"
import { decodeProfileBootstrapV1, type ProfileBootstrapV1 } from "./contracts.ts"
import type { ProfileBootstrapSectionCounts } from "../profileDeferredLoads.ts"
import {
  profileBootstrapViewerKey,
  readProfileBootstrapCache,
  resolveProfileBootstrapCacheProfileId,
  shouldRevalidateProfileBootstrapCache,
  writeProfileBootstrapCache,
  profileBootstrapCanonicalCacheKey,
} from "./profileBootstrapCache.ts"
import {
  beginProfileBootstrapFlight,
  getProfileBootstrapFlight,
  profileBootstrapFlightKey,
} from "./profileBootstrapSingleFlight.ts"

/** True only when PostgREST/Postgres reports the RPC function is not deployed. */
export function isProfileBootstrapRpcUnavailable(error: unknown): boolean {
  if (!(error instanceof BackendV2RpcError)) return false
  const msg = (error.message ?? "").toLowerCase()
  const code = (error.code ?? "").toLowerCase()
  if (isTransientPostgrestError(error)) return false
  return (
    code === "pgrst202" ||
    code === "42883" ||
    msg.includes("could not find the function") ||
    (msg.includes("function") &&
      msg.includes("does not exist") &&
      msg.includes("rpc_v1_profile_bootstrap"))
  )
}

export async function fetchProfileBootstrapV1(
  client: SupabaseClient,
  params: {
    identifier: string
    initialTab?: string
    limit?: number
    cursor?: string | null
    signal?: AbortSignal
  }
): Promise<ProfileBootstrapV1> {
  const rpcParams = {
    p_identifier: params.identifier,
    p_initial_tab: params.initialTab ?? "trades",
    p_limit: params.limit ?? 6,
    p_cursor: params.cursor ?? null,
  }

  return withTransientPostgrestRetry(
    async () => {
      const { data, error } = await client.rpc(
        BackendV2RpcNames.profile,
        rpcParams
      )
      if (error) {
        throw new BackendV2RpcError(
          error.code ?? "rpc_error",
          error.message ?? "Profile bootstrap RPC failed",
          BackendV2RpcNames.profile,
          error
        )
      }
      clearProfileBootstrapRpcUnavailableCache()
      return decodeProfileBootstrapV1(data)
    },
    { signal: params.signal }
  )
}

export type ProfileBootstrapLoadResult = {
  profile: Record<string, unknown> | null
  followersCount: number
  followingCount: number
  isFollowing: boolean
  isRequested: boolean
  followsYou: boolean
  canViewTrades: boolean
  trades: Record<string, unknown>[]
  tradeHasMore: boolean
  publicStats: ProfileBootstrapV1["data"]["public_stats"]
  sectionCounts: ProfileBootstrapSectionCounts | null
}

export function applyProfileBootstrapEngagement(
  engagement: ProfileBootstrapV1["data"]["trade_engagement"]
) {
  if (!engagement) return
  for (const [tradeId, row] of Object.entries(engagement)) {
    writeTradeSocial(tradeId, {
      likes: row.like_count ?? 0,
      liked: row.liked_by_me === true,
      commentCount: row.comment_count ?? 0,
      comments: [],
    })
  }
}

export function mapProfileBootstrapToLoadResult(
  bootstrap: ProfileBootstrapV1,
  viewerId: string | null
): ProfileBootstrapLoadResult {
  const { data } = bootstrap
  const isOwner = data.viewer.is_own_profile
  const tradesRaw = data.trades_page?.items ?? []
  const trades = sanitizeTradesForViewer(tradesRaw, { isOwner })
  applyProfileBootstrapEngagement(data.trade_engagement)
  return {
    profile: data.profile as Record<string, unknown> | null,
    followersCount: data.followers_count ?? 0,
    followingCount: data.following_count ?? 0,
    isFollowing: data.viewer.is_following,
    isRequested: data.viewer.is_requested,
    followsYou: data.viewer.follows_you,
    canViewTrades: data.viewer.can_view_trades,
    trades,
    tradeHasMore: data.trades_page?.page_meta.has_more ?? false,
    publicStats: data.public_stats,
    sectionCounts: (data.section_counts ?? null) as ProfileBootstrapSectionCounts | null,
  }
}

export type ProfileBootstrapLoadSource =
  | "network"
  | "cache_fresh"
  | "cache_stale"
  | "none"

export type ProfileBootstrapResilienceResult = {
  result: ProfileBootstrapLoadResult | null
  source: ProfileBootstrapLoadSource
  /** True when stale cache was returned and network refresh is in flight. */
  revalidating: boolean
  /** Transient failure with no cache to serve. */
  transientError: boolean
}

async function fetchAndCacheProfileBootstrap(
  client: SupabaseClient,
  identifier: string,
  viewerId: string | null,
  signal?: AbortSignal
): Promise<ProfileBootstrapLoadResult | null> {
  const bootstrap = await fetchProfileBootstrapV1(client, {
    identifier,
    initialTab: "trades",
    limit: 6,
    signal,
  })
  if (!bootstrap.meta.found || !bootstrap.data.profile) {
    return null
  }
  const loadResult = mapProfileBootstrapToLoadResult(bootstrap, viewerId)
  const viewerKey = profileBootstrapViewerKey(viewerId)
  const profileId = String(bootstrap.data.profile.id ?? "")
  writeProfileBootstrapCache(
    viewerKey,
    identifier,
    profileId,
    bootstrap,
    loadResult
  )
  return loadResult
}

export async function loadProfileBootstrapWithResilience(
  client: SupabaseClient,
  params: {
    identifier: string
    viewerId: string | null
    signal?: AbortSignal
    /** When true, skip cache read and force network (still single-flight). */
    forceNetwork?: boolean
  }
): Promise<ProfileBootstrapResilienceResult> {
  const viewerKey = profileBootstrapViewerKey(params.viewerId)
  const resolvedProfileId = resolveProfileBootstrapCacheProfileId(
    viewerKey,
    params.identifier
  )
  const flightKey = resolvedProfileId
    ? profileBootstrapCanonicalCacheKey(viewerKey, resolvedProfileId)
    : `${viewerKey}|${params.identifier.trim().toLowerCase()}`

  if (!params.forceNetwork) {
    const cached = readProfileBootstrapCache(viewerKey, params.identifier)
    if (cached.entry) {
      const revalidate = shouldRevalidateProfileBootstrapCache(
        cached.entry.fetchedAt
      )
      if (!revalidate) {
        return {
          result: cached.entry.loadResult,
          source:
            cached.freshness === "fresh" ? "cache_fresh" : "cache_stale",
          revalidating: false,
          transientError: false,
        }
      }
      const inFlight = getProfileBootstrapFlight<ProfileBootstrapLoadResult | null>(
        flightKey
      )
      if (!inFlight) {
        void beginProfileBootstrapFlight(
          flightKey,
          viewerKey,
          params.identifier,
          () =>
            fetchAndCacheProfileBootstrap(
              client,
              params.identifier,
              params.viewerId,
              params.signal
            )
        ).catch(() => {})
      }
      return {
        result: cached.entry.loadResult,
        source: "cache_stale",
        revalidating: true,
        transientError: false,
      }
    }
  }

  try {
    const existing = getProfileBootstrapFlight<ProfileBootstrapLoadResult | null>(
      flightKey
    )
    const result = await (existing ??
      beginProfileBootstrapFlight(
        flightKey,
        viewerKey,
        params.identifier,
        () =>
          fetchAndCacheProfileBootstrap(
            client,
            params.identifier,
            params.viewerId,
            params.signal
          )
      ))
    return {
      result,
      source: "network",
      revalidating: false,
      transientError: false,
    }
  } catch (err) {
    const cached = readProfileBootstrapCache(viewerKey, params.identifier)
    if (cached.entry && isTransientPostgrestError(err)) {
      return {
        result: cached.entry.loadResult,
        source: "cache_stale",
        revalidating: false,
        transientError: false,
      }
    }
    if (isTransientPostgrestError(err)) {
      return {
        result: null,
        source: "none",
        revalidating: false,
        transientError: true,
      }
    }
    if (err instanceof BackendV2RpcError) {
      if (
        process.env.NODE_ENV === "development" ||
        process.env.NEXT_PUBLIC_PROFILE_FETCH_DEBUG === "1"
      ) {
        console.warn("[backendV2.profile] RPC failed; falling back to legacy profile load", {
          rpc: err.rpcName,
          code: err.code,
          message: err.message,
        })
      }
      return {
        result: null,
        source: "none",
        revalidating: false,
        transientError: false,
      }
    }
    throw err
  }
}

export async function tryLoadProfileViaBootstrap(
  client: SupabaseClient,
  identifier: string,
  viewerId: string | null,
  options?: { signal?: AbortSignal; forceNetwork?: boolean }
): Promise<ProfileBootstrapLoadResult | null> {
  if (isProfileBootstrapRpcCachedUnavailable()) return null
  try {
    const loaded = await loadProfileBootstrapWithResilience(client, {
      identifier,
      viewerId,
      signal: options?.signal,
      forceNetwork: options?.forceNetwork,
    })
    if (loaded.transientError) {
      if (
        process.env.NODE_ENV === "development" ||
        process.env.NEXT_PUBLIC_PROFILE_FETCH_DEBUG === "1"
      ) {
        console.warn(
          "[backendV2.profile] transient bootstrap failure; no legacy fallback"
        )
      }
      return loaded.result
    }
    return loaded.result
  } catch (err) {
    if (
      process.env.NODE_ENV === "development" ||
      process.env.NEXT_PUBLIC_PROFILE_FETCH_DEBUG === "1"
    ) {
      console.warn("[backendV2.profile] bootstrap RPC failed", err)
    }
    if (isProfileBootstrapRpcUnavailable(err)) {
      markProfileBootstrapRpcUnavailable()
      return null
    }
    if (isTransientPostgrestError(err)) {
      return null
    }
    return null
  }
}
