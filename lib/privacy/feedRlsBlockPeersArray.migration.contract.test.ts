import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const root = process.cwd()
const migrationPath = path.join(
  root,
  "supabase/migrations/20261027160000_feed_rls_block_peers_array.sql"
)

describe("feed RLS block peers array migration (phase 1)", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("introduces rls_viewer_block_peer_ids and parity helper", () => {
    assert.match(sql, /function public\.rls_viewer_block_peer_ids\(\)/)
    assert.match(sql, /function public\.rls_passes_block_peer_check\(p_author_id uuid\)/)
    assert.match(sql, /get_active_block_peer_ids\(\)/)
    assert.match(sql, /grant execute on function public\.rls_viewer_block_peer_ids\(\) to anon/)
    assert.doesNotMatch(sql, /grant execute on function public\.get_active_block_peer_ids\(\) to anon/)
    assert.match(sql, /grant execute on function public\.get_active_block_peer_ids\(\) to authenticated/)
  })

  it("does not call viewer_has_block_with or rls_passes_block_peer_check in policy bodies", () => {
    const policySection = sql.slice(sql.indexOf('drop policy if exists "posts_select_public"'))
    assert.doesNotMatch(policySection, /viewer_has_block_with\s*\(/)
    assert.doesNotMatch(policySection, /rls_passes_block_peer_check\s*\(/)
  })

  it("updates feed-touch SELECT policies including profile_posts gap", () => {
    for (const name of [
      "posts_select_public",
      "profile_posts_select_visible",
      "stories_select_visible",
      "reels_select_visible",
      "trades_select_public",
      "trades_select_followed_private_profile",
      "achievements_select_public",
      "achievement_posts_select_authenticated",
      "profiles_select_hide_blocked",
    ]) {
      assert.match(sql, new RegExp(`"${name}"`))
      assert.match(sql, /rls_viewer_block_peer_ids/)
    }
  })

  it("does not modify rpc_v1_feed_bootstrap or trade payload helpers", () => {
    assert.doesNotMatch(sql, /rpc_v1_feed_bootstrap/)
    assert.doesNotMatch(sql, /_v1_feed_post_trade_payload/)
  })
})
