import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))
import { describe, it } from "node:test"
import { decodeFeedBootstrapV1 } from "./contracts.ts"
import { feedBootstrapFixture } from "./fixtures.ts"
import { feedContractFixtures } from "./feedContractFixtures.ts"
import { validateFeedBootstrapContract, isCompositeFeedCursor, compareFeedBootstrapSemantics, } from "./feedContractSchema.ts"
import { compareFeedBootstraps } from "./feedBootstrapCompare.ts"
import assert from "node:assert/strict"

const FIXTURE_CASES = [
  ["globalAll", feedContractFixtures.globalAll],
  ["globalTrades", feedContractFixtures.globalTrades],
  ["globalPosts", feedContractFixtures.globalPosts],
  ["globalReels", feedContractFixtures.globalReels],
  ["globalAchievements", feedContractFixtures.globalAchievements],
  ["followingAll", feedContractFixtures.followingAll],
  ["followingTrades", feedContractFixtures.followingTrades],
  ["followingPosts", feedContractFixtures.followingPosts],
  ["followingReels", feedContractFixtures.followingReels],
  ["followingAchievements", feedContractFixtures.followingAchievements],
  ["emptyFollowing", feedContractFixtures.emptyFollowing],
  ["equalTimestampBoundary", feedContractFixtures.equalTimestampBoundary],
  ["paginationBoundary", feedContractFixtures.paginationBoundary],
  ["withStories", feedContractFixtures.withStories],
  ["viewerLikedCommented", feedContractFixtures.viewerLikedCommented],
  ["noAvatarNoScreenshot", feedContractFixtures.noAvatarNoScreenshot],
  ["linkedTradeReel", feedContractFixtures.linkedTradeReel],
  ["goldenFixture", feedBootstrapFixture],
]

describe("Phase B2 — Feed bootstrap contract shape", () => {
  for (const [name, fixture] of FIXTURE_CASES) {
    it(`validates ${name} fixture shape`, () => {
      const raw = JSON.parse(JSON.stringify(fixture))
      const decoded = decodeFeedBootstrapV1(raw)
      const violations = validateFeedBootstrapContract(decoded)
      assert.deepEqual(
        violations,
        [],
        `${name}: ${violations.map((v) => `${v.path} ${v.message}`).join("; ")}`
      )
    })
  }

  it("empty following feed uses [] not null for items and following_ids_echo", () => {
    const decoded = decodeFeedBootstrapV1(
      JSON.parse(JSON.stringify(feedContractFixtures.emptyFollowing))
    )
    assert.deepEqual(decoded.data.items, [])
    assert.deepEqual(decoded.data.following_ids_echo, [])
    assert.equal(decoded.data.next_cursor, null)
    assert.equal(decoded.data.page_meta.has_more, false)
  })

  it("global scope stories must be empty in contract validator", () => {
    const bad = JSON.parse(JSON.stringify(feedContractFixtures.globalAll))
    bad.data.stories = [
      {
        id: "s1",
        user_id: "u1",
        image_url: "x",
        created_at: "2026-01-01T00:00:00.000Z",
      },
    ]
    const decoded = decodeFeedBootstrapV1(bad)
    const violations = validateFeedBootstrapContract(decoded)
    assert.ok(violations.some((v) => v.path === "data.stories"))
  })

  it("composite cursor format is recognized", () => {
    assert.equal(
      isCompositeFeedCursor("2026-08-20T12:00:00.000Z|post|11111111-1111-1111-1111-111111111111"),
      true
    )
    assert.equal(isCompositeFeedCursor("2026-08-20T12:00:00.000Z"), false)
  })

  it("pagination boundary emits composite next_cursor when has_more", () => {
    const decoded = decodeFeedBootstrapV1(
      JSON.parse(JSON.stringify(feedContractFixtures.paginationBoundary))
    )
    assert.equal(decoded.data.page_meta.has_more, true)
    assert.ok(decoded.data.next_cursor)
    assert.ok(isCompositeFeedCursor(decoded.data.next_cursor))
  })

  it("compare helper detects item id drift", () => {
    const a = decodeFeedBootstrapV1(
      JSON.parse(JSON.stringify(feedContractFixtures.followingAll))
    )
    const b = decodeFeedBootstrapV1(
      JSON.parse(JSON.stringify(feedContractFixtures.followingAll))
    )
    b.data.items = []
    const mismatches = compareFeedBootstraps(a, b)
    assert.ok(mismatches.some((m) => m.path === "items.ids"))
  })

  it("semantic compare ignores server_time", () => {
    const a = decodeFeedBootstrapV1(
      JSON.parse(JSON.stringify(feedContractFixtures.globalAll))
    )
    const b = decodeFeedBootstrapV1(
      JSON.parse(JSON.stringify(feedContractFixtures.globalAll))
    )
    b.meta.server_time = "2099-01-01T00:00:00.000Z"
    const violations = compareFeedBootstrapSemantics(a, b)
    assert.deepEqual(violations, [])
  })
})

describe("Phase B2 — Feed RPC migration file contract freeze", () => {
  it("optimized migration defines text cursor and helper functions", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260820224542_rpc_v1_feed_bootstrap_optimize.sql"
      ),
      "utf8"
    )
    assert.match(sql, /security invoker/i)
    assert.match(sql, /set search_path = public/i)
    assert.match(sql, /grant execute on function public\.rpc_v1_feed_bootstrap\(text, text, integer, text\) to authenticated/i)
    assert.match(sql, /_v1_feed_parse_cursor/)
    assert.match(sql, /_v1_feed_before_cursor/)
    assert.match(sql, /profile_posts_user_id_created_at_idx/)
    assert.match(sql, /drop function if exists public\.rpc_v1_feed_bootstrap\(text, text, integer, timestamptz\)/)
  })

  it("rollback migration restores timestamptz cursor RPC", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/rollback/20260820224542_rpc_v1_feed_bootstrap_rollback.sql"
      ),
      "utf8"
    )
    assert.match(sql, /p_cursor timestamptz default null/)
    assert.match(sql, /drop function if exists public\.rpc_v1_feed_bootstrap\(text, text, integer, text\)/)
  })
})
export {}
