import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  isNonRetryablePostgrestError,
  isTransientPostgrestError,
} from "./postgrestTransientRetry.ts"
import {
  PROFILE_BOOTSTRAP_FRESH_MS,
  profileBootstrapCacheFreshness,
  profileBootstrapCanonicalCacheKey,
  profileBootstrapViewerKey,
  readProfileBootstrapCache,
  writeProfileBootstrapCache,
  __resetProfileBootstrapCacheForTests,
} from "./profileBootstrap/profileBootstrapCache.ts"
import type { ProfileBootstrapV1 } from "./profileBootstrap/contracts.ts"

describe("postgrestTransientRetry", () => {
  it("classifies PGRST002 as transient", () => {
    assert.equal(
      isTransientPostgrestError({
        code: "PGRST002",
        message: "Could not query the database for the schema cache. Retrying.",
      }),
      true
    )
  })

  it("does not retry PGRST202 missing function", () => {
    assert.equal(isNonRetryablePostgrestError({ code: "PGRST202" }), true)
    assert.equal(isTransientPostgrestError({ code: "PGRST202" }), false)
  })
})

describe("profileBootstrapCache", () => {
  it("keys cache canonically by viewer and profile id", () => {
    assert.equal(
      profileBootstrapCanonicalCacheKey("u1", "p1-uuid"),
      "u1|p1-uuid"
    )
    assert.equal(profileBootstrapViewerKey(null), "anon")
  })

  it("computes freshness tiers", () => {
    assert.equal(profileBootstrapCacheFreshness(Date.now()), "fresh")
    assert.equal(
      profileBootstrapCacheFreshness(Date.now() - PROFILE_BOOTSTRAP_FRESH_MS - 1),
      "soft_stale"
    )
  })

  it("does not share cache across viewers", () => {
    __resetProfileBootstrapCacheForTests()
    assert.equal(readProfileBootstrapCache("u2", "alice").entry, null)
    __resetProfileBootstrapCacheForTests()
  })

  it("aliases username and uuid to canonical profile id entry", () => {
    __resetProfileBootstrapCacheForTests()
    const boot = {
      meta: { contract_version: 1, found: true },
      data: {
        profile: {
          id: "p1-uuid",
          username: "alice",
          bio: null,
          avatar_url: null,
          trading_style: null,
          trader_type: null,
          primary_market: null,
          started_trading: null,
          is_private: false,
          created_at: null,
        },
        viewer: {
          is_own_profile: false,
          is_following: false,
          is_requested: false,
          follows_you: false,
          can_view_trades: true,
        },
        followers_count: 0,
        following_count: 0,
        active_tab: "trades",
        trades_page: {
          items: [],
          page_meta: {
            limit: 6,
            returned: 0,
            has_more: false,
            next_cursor: null,
          },
        },
        public_stats: null,
        section_counts: {},
        trade_engagement: {},
      },
    } satisfies ProfileBootstrapV1
    writeProfileBootstrapCache("u1", "alice", "p1-uuid", boot, {
      profile: boot.data.profile,
      followersCount: 0,
      followingCount: 0,
      isFollowing: false,
      isRequested: false,
      followsYou: false,
      canViewTrades: true,
      trades: [],
      tradeHasMore: false,
      publicStats: null,
      sectionCounts: null,
    })
    const byUsername = readProfileBootstrapCache("u1", "alice")
    const byUuid = readProfileBootstrapCache("u1", "p1-uuid")
    assert.equal(byUsername.entry?.profileId, "p1-uuid")
    assert.equal(byUuid.entry?.profileId, "p1-uuid")
    assert.equal(byUsername.entry, byUuid.entry)
    __resetProfileBootstrapCacheForTests()
  })
})
