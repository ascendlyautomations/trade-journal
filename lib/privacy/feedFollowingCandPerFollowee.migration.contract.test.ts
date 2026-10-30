import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "../..")
const migrationPath = path.join(
  root,
  "supabase/migrations/20261027140000_feed_following_cand_per_followee.sql"
)

function extractDollarBlock(migrationSql, tag) {
  const re = new RegExp(`\\$${tag}\\$([\\s\\S]*?)\\$${tag}\\$`, "g")
  return [...migrationSql.matchAll(re)].map((m) => m[1])
}

function simulateProductionRpcBody() {
  const explorePath = path.join(
    root,
    "supabase/migrations/20260915230000_explore_mode_guest_security_hardening.sql"
  )
  const exploreSql = fs.readFileSync(explorePath, "utf8")
  const start = exploreSql.indexOf("create or replace function public.rpc_v1_feed_bootstrap(")
  const bodyStart = exploreSql.indexOf("as $$\n", start)
  const bodyEnd = exploreSql.indexOf("\n$$;", bodyStart)
  let body = exploreSql.slice(bodyStart + "as $$\n".length, bodyEnd)

  body = body.replace(
    "v_following uuid[] := '{}'::uuid[];",
    "v_following uuid[] := '{}'::uuid[];\n  v_block_peers uuid[] := '{}'::uuid[];"
  )
  body = body.replace(
    `  if v_uid is not null then
    select coalesce(array_agg(f.following_id), '{}'::uuid[])
    into v_following
    from public.followers f
    where f.follower_id = v_uid;
  end if;

  if v_scope = 'following' and cardinality(v_following) = 0 then`,
    `  if v_uid is not null then
    select coalesce(array_agg(f.following_id), '{}'::uuid[])
    into v_following
    from public.followers f
    where f.follower_id = v_uid;
  end if;

  if not v_guest and v_uid is not null then
    select public.get_active_block_peer_ids() into v_block_peers;
  end if;

  if v_scope = 'following' and cardinality(v_following) = 0 then`
  )
  for (const [from, to] of [
    ["and not public.users_have_active_block(v_uid, p.user_id)", "and (v_guest or not (p.user_id = any (v_block_peers)))"],
    ["and not public.users_have_active_block(v_uid, pp.user_id)", "and (v_guest or not (pp.user_id = any (v_block_peers)))"],
    ["and not public.users_have_active_block(v_uid, ap.user_id)", "and (v_guest or not (ap.user_id = any (v_block_peers)))"],
    ["and not public.users_have_active_block(v_uid, r.user_id)", "and (v_guest or not (r.user_id = any (v_block_peers)))"],
    ["or not public.users_have_active_block(v_uid, s.user_id)", "or v_guest or not (s.user_id = any (v_block_peers))"],
  ] as const) {
    body = body.replaceAll(from, to)
  }
  body = body.replace("left join public.trades t on t.id = p.trade_id", "")
  body = body.replace(
    "public._v1_feed_post_trade_payload(t, tr, v_guest)",
    "public._v1_feed_post_trade_payload(p.trade_id, tr, v_guest)"
  )
  body = body.replace(
    "from public.trades tx\n                where tx.id = p.trade_id\n                  and coalesce(tx.is_public, false) = true",
    "from public.trades_public_read tx\n                where tx.id = p.trade_id"
  )
  return body
}

function applyCandMigration(body, migrationSql) {
  const tags = ["old_post", "new_post", "old_pp", "new_pp", "old_ap", "new_ap", "old_rl", "new_rl"]
  const blocks = Object.fromEntries(tags.map((t) => [t, extractDollarBlock(migrationSql, t)[0]]))
  let updated = body
  for (const pair of [
    ["old_post", "new_post"],
    ["old_pp", "new_pp"],
    ["old_ap", "new_ap"],
    ["old_rl", "new_rl"],
  ] as const) {
    const old = blocks[pair[0]]
    const neu = blocks[pair[1]]
    assert.ok(body.includes(old), `${pair[0]} anchor must match simulated production body`)
    assert.equal(updated.split(old).length - 1, 1, `${pair[0]} anchor must appear once`)
    updated = updated.replace(old, neu)
  }
  return updated
}

describe("feed following cand per-followee migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("patches all four cand branches with lateral merge CTEs", () => {
    assert.match(sql, /post_merge/)
    assert.match(sql, /profile_post_merge/)
    assert.match(sql, /achievement_post_merge/)
    assert.match(sql, /reel_merge/)
    assert.match(sql, /cross join lateral/i)
    assert.match(sql, /case when v_scope = 'following' then v_following else '{}'::uuid\[\] end/)
  })

  it("requires block peers once and preserves invoker", () => {
    assert.match(sql, /get_active_block_peer_ids\(\)/)
    assert.match(sql, /must stay security invoker/)
    assert.match(sql, /if position\('post_merge' in src\) > 0 then/)
    assert.match(sql, /partial following cand patch \(fail closed\)/)
    assert.match(sql, /users_have_active_block\(v_uid,/)
    assert.match(sql, /must remain security invoker after patch/)
  })

  it("rollback artifact restores pre-migration function without lateral merge markers", () => {
    const rollbackPath = path.join(
      root,
      "supabase/migrations/rollback/20261027140000_feed_following_cand_per_followee_rollback.sql"
    )
    const rollback = fs.readFileSync(rollbackPath, "utf8")
    assert.match(rollback, /create or replace function public\.rpc_v1_feed_bootstrap/i)
    assert.match(rollback, /get_active_block_peer_ids\(\)/)
    assert.doesNotMatch(rollback, /post_merge/)
    assert.doesNotMatch(
      rollback,
      /case when v_scope = 'following' then v_following else '{}'::uuid\[\] end/
    )
  })

  it("anchors match production posts branch with trades_public_read guest filter", () => {
    assert.match(sql, /trades_public_read tx/)
    assert.match(sql, /feed following cand posts branch patch failed/)
    assert.match(sql, /feed following cand reels branch patch failed/)
  })

  it("applies deterministically to block-peers + safe-trade production-shaped body", () => {
    const body = simulateProductionRpcBody()
    const patched = applyCandMigration(body, sql)
    assert.notEqual(patched, body)
    assert.match(patched, /post_merge/)
    assert.match(patched, /profile_post_merge/)
    assert.match(patched, /achievement_post_merge/)
    assert.match(patched, /reel_merge/)
    assert.doesNotMatch(patched, /users_have_active_block\(v_uid,/)
    assert.match(patched, /ranked as \(/)
    assert.match(patched, /feed_engagement_counts/)
    assert.match(patched, /_v1_feed_kind_rank/)
    assert.match(patched, /story_rows/)
    assert.match(patched, /get_active_block_peer_ids\(\)/)
    assert.doesNotMatch(patched, /\(v_scope = 'following' and p\.user_id = any \(v_following\)\)/)
    assert.match(patched, /where v_scope = 'global'\s+and v_include_trades/)
  })
})
