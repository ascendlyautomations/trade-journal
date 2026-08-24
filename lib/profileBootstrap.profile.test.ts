import { describe, it } from "node:test"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))
import { computeProfileOverviewStats, computeProfileOverviewWinRate, computeProfileAnalyticsStats, overviewStatsFromBootstrapPublicStats, shouldFetchProfileSummaryTrades, } from "./profilePublicStatistics.ts"
import {
  PROFILE_ROOM_SELECT,
  profileRoomKeyFromRow,
  resolveProfileHasActiveStory,
  resolveProfileHasRoom,
} from "./profileDeferredLoads.ts"
import {
  __resetBackendV2FlagsForTests,
  __setBackendV2FlagForTests,
  isBackendV2Enabled,
  resolveBackendV2Flag,
} from "./backendV2/flags.ts"
import {
  isProfileBootstrapRpcUnavailable,
  tryLoadProfileViaBootstrap,
} from "./profileBootstrap/profileBootstrapRepository.ts"
import { __resetProfileBootstrapCacheForTests } from "./profileBootstrap/profileBootstrapCache.ts"
import { BackendV2RpcError } from "./backendV2/rpcClient.ts"
import { BackendV2RpcNames } from "./backendV2/versioning.ts"
import type { SupabaseClient } from "@supabase/supabase-js"
import {
  isProfileBootstrapRpcCachedUnavailable,
  resetProfileBootstrapRpcAvailabilityForTests,
} from "./profileBootstrap/profileV1Availability.ts"
import assert from "node:assert/strict"

type LegacyTableName =
  | "profiles"
  | "followers"
  | "trades"
  | "trade_likes"
  | "trade_comments"

type LegacyTableCallCounts = Record<LegacyTableName, number>

function createProfileBootstrapSupabaseMock(
  otherProfileId: string,
  handlers: {
    onRpc: (name: string, args: Record<string, unknown>) => void
    onFrom: (table: LegacyTableName) => void
  }
): SupabaseClient {
  const mock = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      handlers.onRpc(name, args)
      if (name === BackendV2RpcNames.profile) {
        return {
          data: {
            meta: { contract_version: 1, found: true },
            data: {
              profile: {
                id: otherProfileId,
                username: "otheruser",
                bio: null,
                avatar_url: null,
                is_private: false,
              },
              viewer: {
                is_own_profile: false,
                can_view_trades: true,
                is_following: false,
                is_requested: false,
                follows_you: false,
              },
              followers_count: 3,
              following_count: 2,
              section_counts: {},
              public_stats: { total_trades: 1, wins: 1, total_pnl: 10 },
              active_tab: "trades",
              trades_page: {
                items: [
                  { id: "t1", user_id: otherProfileId, is_public: true, pnl: 10 },
                ],
                page_meta: {
                  limit: 6,
                  returned: 1,
                  has_more: false,
                  next_cursor: null,
                },
              },
              trade_engagement: {
                t1: { like_count: 2, liked_by_me: false, comment_count: 1 },
              },
            },
          },
          error: null,
        }
      }
      return { data: null, error: { message: "unexpected rpc", code: "XX" } }
    },
    from: (table: string) => {
      if (
        table === "profiles" ||
        table === "followers" ||
        table === "trades" ||
        table === "trade_likes" ||
        table === "trade_comments"
      ) {
        handlers.onFrom(table)
      }
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({ data: null, error: null }),
          }),
        }),
      }
    },
  }
  return mock as unknown as SupabaseClient
}

function createFailingProfileBootstrapSupabaseMock(): SupabaseClient {
  const mock = {
    rpc: async () => ({
      data: null,
      error: {
        code: "42703",
        message: "column s.expires_at does not exist",
      },
    }),
  }
  return mock as unknown as SupabaseClient
}

describe("profilePublicStatistics", () => {
  const sample = [
    { pnl: 100, mode: "live", account_type: "live", is_public: true },
    { pnl: -50, mode: "live", account_type: "live", is_public: true },
    { pnl: 25, mode: "backtest", account_type: "backtest", is_public: true },
    { pnl: 10, mode: "funded", account_type: "funded", is_public: true },
  ]

  it("overview excludes backtests", () => {
    const stats = computeProfileOverviewStats(sample)
    assert.equal(stats.totalTrades, 3)
    assert.equal(stats.wins, 2)
    assert.equal(stats.totalPnl, 60)
    assert.equal(computeProfileOverviewWinRate(stats), (2 / 3) * 100)
  })

  it("analytics respects mode filter and public flag", () => {
    const all = computeProfileAnalyticsStats(sample, "all")
    assert.equal(all.totalTrades, 3)
    const funded = computeProfileAnalyticsStats(sample, "funded")
    assert.equal(funded.totalTrades, 1)
  })

  it("golden breakeven and null pnl", () => {
    const stats = computeProfileOverviewStats([
      { pnl: 0, mode: "live", account_type: "live" },
      { pnl: null, mode: "live", account_type: "live" },
    ])
    assert.equal(stats.wins, 0)
    assert.equal(stats.totalTrades, 2)
    assert.equal(stats.totalPnl, 0)
  })

  it("maps bootstrap public_stats to overview aggregate", () => {
    const stats = overviewStatsFromBootstrapPublicStats({
      total_trades: 10,
      wins: 6,
      total_pnl: 420,
    })
    assert.equal(stats.totalTrades, 10)
    assert.equal(stats.wins, 6)
    assert.equal(stats.totalPnl, 420)
    assert.equal(stats.avgRr, null)
    assert.equal(computeProfileOverviewWinRate(stats), 60)
  })

  it("skips summary fetch when bootstrap public_stats are present", () => {
    assert.equal(
      shouldFetchProfileSummaryTrades({
        profileId: "user-1",
        canViewTrades: true,
        summaryReady: false,
        bootstrapPublicStats: { total_trades: 1, wins: 1, total_pnl: 10 },
      }),
      false
    )
    assert.equal(
      shouldFetchProfileSummaryTrades({
        profileId: "user-1",
        canViewTrades: true,
        summaryReady: false,
        bootstrapPublicStats: null,
      }),
      true
    )
  })
})

describe("Profile deferred loads", () => {
  it("uses bootstrap has_active_story for ring before story rows load", () => {
    assert.equal(
      resolveProfileHasActiveStory({
        bootstrapHasActiveStory: true,
        storiesByUser: {},
        profileId: "u1",
      }),
      true
    )
    assert.equal(
      resolveProfileHasActiveStory({
        bootstrapHasActiveStory: false,
        storiesByUser: {},
        profileId: "u1",
      }),
      false
    )
  })

  it("uses bootstrap has_room before room row fetch", () => {
    assert.equal(
      resolveProfileHasRoom({ bootstrapHasRoom: true, roomRow: null }),
      true
    )
    assert.equal(
      resolveProfileHasRoom({ bootstrapHasRoom: false, roomRow: null }),
      false
    )
  })

  it("room select is minimal and excludes wildcard", () => {
    assert.equal(PROFILE_ROOM_SELECT.includes("*"), false)
    assert.match(PROFILE_ROOM_SELECT, /slug/)
    assert.match(PROFILE_ROOM_SELECT, /show_on_profile/)
  })

  it("ProfileTradeCard disables automatic trade route prefetch", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../app/components/profile/ProfileTradeCard.tsx"),
      "utf8"
    )
    assert.match(src, /IntentPrefetchLink/)
    assert.match(src, /prefetch=\{false\}/)
    assert.doesNotMatch(src, /import Link from "next\/link"/)
  })

  it("Profile page defers stories and rooms on idle mount", () => {
    const pageSrc = fs.readFileSync(
      path.join(__dirname, "../app/profile/[id]/page.tsx"),
      "utf8"
    )
    assert.match(pageSrc, /handleOpenProfileStory/)
    assert.match(pageSrc, /profileStoriesLoadRequested/)
    assert.match(pageSrc, /ensureProfileRoomLoaded/)
    assert.doesNotMatch(pageSrc, /select\("\*"\)[\s\S]{0,40}owner_user_id/)
    assert.doesNotMatch(pageSrc, /IntersectionObserver[\s\S]{0,120}setProfileStories/)
  })
})

describe("Profile bootstrap migration security", () => {
  it("uses SECURITY INVOKER and grants minimum roles", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../supabase/migrations/20260821023406_rpc_v1_profile_bootstrap.sql"
      ),
      "utf8"
    )
    assert.match(sql, /security invoker/i)
    assert.match(sql, /stable/i)
    assert.match(sql, /revoke all.*from public/i)
    assert.match(sql, /grant execute.*to authenticated/i)
  })

  it("repair migration fixes story expiration without expires_at column", () => {
    const repair = fs.readFileSync(
      path.join(
        __dirname,
        "../supabase/migrations/20260821041500_fix_rpc_v1_profile_bootstrap_story_expiration.sql"
      ),
      "utf8"
    )
    assert.doesNotMatch(repair, /where s\.user_id[\s\S]{0,120}s\.expires_at/)
    assert.match(
      repair,
      /s\.created_at\s*>\s*\(timezone\('utc',\s*now\(\)\)\s*-\s*interval\s*'24 hours'\)/
    )
    assert.match(repair, /security invoker/i)
    assert.match(repair, /grant execute.*to authenticated/i)
  })
})

describe("Profile bootstrap flag activation", () => {
  it("reads NEXT_PUBLIC_BACKEND_V2_PROFILE at build time", () => {
    const flagsSrc = fs.readFileSync(
      path.join(__dirname, "./backendV2/flags.ts"),
      "utf8"
    )
    assert.match(flagsSrc, /NEXT_PUBLIC_BACKEND_V2_PROFILE/)
    assert.match(flagsSrc, /case "profile":/)
  })

  it("enables profile via env override", () => {
    const prev = process.env.NEXT_PUBLIC_BACKEND_V2_PROFILE
    process.env.NEXT_PUBLIC_BACKEND_V2_PROFILE = "1"
    __resetBackendV2FlagsForTests()
    try {
      const resolved = resolveBackendV2Flag("profile")
      assert.equal(resolved.enabled, true)
      assert.equal(resolved.source, "env")
      assert.equal(isBackendV2Enabled("profile"), true)
    } finally {
      __resetBackendV2FlagsForTests()
      if (prev === undefined) delete process.env.NEXT_PUBLIC_BACKEND_V2_PROFILE
      else process.env.NEXT_PUBLIC_BACKEND_V2_PROFILE = prev
    }
  })

  it("profile flag can be toggled via env without hardcoding enabled in .env.local", () => {
    const envPath = path.join(__dirname, "../.env.local")
    if (!fs.existsSync(envPath)) return
    const envLocal = fs.readFileSync(envPath, "utf8")
    assert.match(envLocal, /NEXT_PUBLIC_BACKEND_V2_PROFILE/)
  })
})

describe("Profile own-path vs bootstrap wiring", () => {
  const VIEWER = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  const OTHER = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

  it("own profile resolves session header before bootstrap RPC in fetchProfile", () => {
    const pageSrc = fs.readFileSync(
      path.join(__dirname, "../app/profile/[id]/page.tsx"),
      "utf8"
    )
    const fetchStart = pageSrc.indexOf("async function fetchProfile(")
    assert.ok(fetchStart >= 0)
    const fetchBody = pageSrc.slice(fetchStart, fetchStart + 12000)
    const ownIdx = fetchBody.indexOf("resolveOwnProfileHeaderFromSession")
    const bootIdx = fetchBody.indexOf("loadProfileBootstrapWithResilience")
    assert.ok(ownIdx >= 0 && bootIdx >= 0)
    assert.ok(ownIdx < bootIdx, "own session header resolves before bootstrap RPC")
    assert.match(
      fetchBody,
      /if \(ownHeader\) \{[\s\S]*?return[\s\S]*?\}[\s\S]*?if \(isBackendV2Enabled\("profile"\)\)/
    )
    const ownPathSrc = fs.readFileSync(
      path.join(__dirname, "./profileOwnPath.ts"),
      "utf8"
    )
    assert.match(ownPathSrc, /readSessionBootstrapCache/)
    assert.match(ownPathSrc, /resolveOwnProfileHeaderFromSession/)
  })

  it("other profile with flag ON calls rpc_v1_profile_bootstrap once", async () => {
    resetProfileBootstrapRpcAvailabilityForTests()
    __resetProfileBootstrapCacheForTests()
    let rpcCalls = 0
    const legacyCalls: LegacyTableCallCounts = {
      profiles: 0,
      followers: 0,
      trades: 0,
      trade_likes: 0,
      trade_comments: 0,
    }

    const mockClient = createProfileBootstrapSupabaseMock(OTHER, {
      onRpc: (name, args) => {
        if (name === BackendV2RpcNames.profile) {
          rpcCalls += 1
          assert.equal(args.p_identifier, "otheruser")
          assert.equal(args.p_initial_tab, "trades")
        }
      },
      onFrom: (table) => {
        legacyCalls[table] += 1
      },
    })

    const result = await tryLoadProfileViaBootstrap(
      mockClient,
      "otheruser",
      VIEWER
    )
    assert.ok(result)
    assert.equal(result.profile?.username, "otheruser")
    assert.equal(rpcCalls, 1)
    assert.equal(legacyCalls.profiles, 0)
    assert.equal(legacyCalls.followers, 0)
    assert.equal(legacyCalls.trades, 0)
    assert.equal(legacyCalls.trade_likes, 0)
    assert.equal(legacyCalls.trade_comments, 0)
  })

  it("fetchProfile returns before legacy queries when bootstrap succeeds", () => {
    const pageSrc = fs.readFileSync(
      path.join(__dirname, "../app/profile/[id]/page.tsx"),
      "utf8"
    )
    const fetchStart = pageSrc.indexOf("async function fetchProfile(")
    assert.ok(fetchStart >= 0)
    const fetchBody = pageSrc.slice(fetchStart, fetchStart + 12000)
    const bootStart = fetchBody.indexOf('if (isBackendV2Enabled("profile"))')
    const bootEnd = fetchBody.indexOf('let profileQuery = supabase.from("profiles")')
    assert.ok(bootStart >= 0 && bootEnd > bootStart)
    const bootBlock = fetchBody.slice(bootStart, bootEnd)
    assert.match(bootBlock, /loadProfileBootstrapWithResilience/)
    assert.match(bootBlock, /return/)
    assert.doesNotMatch(bootBlock, /applyProfileMetadata/)
    assert.doesNotMatch(bootBlock, /profileQuery/)
  })

  it("maps RPC name to rpc_v1_profile_bootstrap", () => {
    assert.equal(BackendV2RpcNames.profile, "rpc_v1_profile_bootstrap")
  })

  it("SQL errors are not treated as missing RPC", () => {
    const err = new BackendV2RpcError(
      "42703",
      'column s.expires_at does not exist in rpc_v1_profile_bootstrap',
      BackendV2RpcNames.profile
    )
    assert.equal(isProfileBootstrapRpcUnavailable(err), false)
  })

  it("missing-function errors are treated as unavailable", () => {
    const err = new BackendV2RpcError(
      "42883",
      "function rpc_v1_profile_bootstrap(text, text, integer, text) does not exist",
      BackendV2RpcNames.profile
    )
    assert.equal(isProfileBootstrapRpcUnavailable(err), true)
  })

  it("RPC SQL failure falls back without caching unavailable", async () => {
    resetProfileBootstrapRpcAvailabilityForTests()
    __resetProfileBootstrapCacheForTests()
    const mockClient = createFailingProfileBootstrapSupabaseMock()
    const result = await tryLoadProfileViaBootstrap(
      mockClient,
      "otheruser",
      VIEWER
    )
    assert.equal(result, null)
    assert.equal(isProfileBootstrapRpcCachedUnavailable(), false)
  })

  it("successful bootstrap skips legacy summary-trades loader", () => {
    const pageSrc = fs.readFileSync(
      path.join(__dirname, "../app/profile/[id]/page.tsx"),
      "utf8"
    )
    assert.match(pageSrc, /shouldFetchProfileSummaryTrades/)
    assert.match(pageSrc, /bootstrapPublicStats/)
    assert.match(pageSrc, /overviewStatsFromBootstrapPublicStats/)
    assert.match(
      pageSrc,
      /if \(boot\.publicStats\) \{[\s\S]*?setSummaryReady\(true\)/
    )
  })

  it("analytics tab selection gates full trades fetch", () => {
    const pageSrc = fs.readFileSync(
      path.join(__dirname, "../app/profile/[id]/page.tsx"),
      "utf8"
    )
    assert.match(
      pageSrc,
      /analyticsRequested\s*=\s*[\s\S]*activeTab === "calendar"[\s\S]*activeTab === "stats"/
    )
    assert.match(pageSrc, /!analyticsRequested/)
    assert.match(pageSrc, /fetchAllTradesForAnalytics/)
  })
})
export {}
