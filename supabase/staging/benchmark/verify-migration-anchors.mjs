#!/usr/bin/env node
/**
 * Validates DO-block old_string anchors from 20261027140000 against a function body.
 * Usage: node verify-migration-anchors.mjs [path-to-function-body.sql]
 * Without arg, simulates explore + block-peers patch from repo migrations.
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../..")

function extractDollarBlock(migrationSql, tag) {
  const re = new RegExp(`\\$${tag}\\$([\\s\\S]*?)\\$${tag}\\$`, "g")
  const blocks = [...migrationSql.matchAll(re)]
  return blocks.map((m) => m[1])
}

function simulateProductionBody() {
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
  ]) {
    body = body.replaceAll(from, to)
  }

  body = body.replace(
    "left join public.trades t on t.id = p.trade_id",
    ""
  )
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
  const olds = [
    extractDollarBlock(migrationSql, "old_post")[0],
    extractDollarBlock(migrationSql, "old_pp")[0],
    extractDollarBlock(migrationSql, "old_ap")[0],
    extractDollarBlock(migrationSql, "old_rl")[0],
  ]
  const news = [
    extractDollarBlock(migrationSql, "new_post")[0],
    extractDollarBlock(migrationSql, "new_pp")[0],
    extractDollarBlock(migrationSql, "new_ap")[0],
    extractDollarBlock(migrationSql, "new_rl")[0],
  ]
  let updated = body
  for (let i = 0; i < olds.length; i++) {
    if (!updated.includes(olds[i])) {
      throw new Error(`Anchor ${i} missing from body`)
    }
    const count = updated.split(olds[i]).length - 1
    if (count !== 1) {
      throw new Error(`Anchor ${i} expected once, found ${count}`)
    }
    updated = updated.replace(olds[i], news[i])
  }
  return updated
}

function assertPreserves(body, patched) {
  const markers = [
    "ranked as (",
    "feed_engagement_counts",
    "_v1_feed_kind_rank",
    "story_rows",
    "_v1_feed_post_trade_payload",
    "get_active_block_peer_ids()",
  ]
  for (const m of markers) {
    if (!patched.includes(m)) throw new Error(`Missing after patch: ${m}`)
  }
  if (patched.includes("users_have_active_block(v_uid,")) {
    throw new Error("Per-row block check reintroduced")
  }
  if (/security definer/i.test(patched)) throw new Error("security definer detected")
  if (body === patched) throw new Error("Patch made no changes")
  if (patched.split(") post_merge").length - 1 !== 1) throw new Error("post_merge count")
}

const migPath = path.join(
  root,
  "supabase/migrations/20261027140000_feed_following_cand_per_followee.sql"
)
const migrationSql = fs.readFileSync(migPath, "utf8")
const body = process.argv[2]
  ? fs.readFileSync(process.argv[2], "utf8")
  : simulateProductionBody()

const patched = applyCandMigration(body, migrationSql)
assertPreserves(body, patched)

// Idempotent second apply should fail our anchor check (anchors gone) — matches DB idempotent early return on post_merge
if (patched.includes("post_merge")) {
  try {
    applyCandMigration(patched, migrationSql)
    console.error("FAIL: second apply should not find anchors")
    process.exit(1)
  } catch {
    console.log("OK: second apply correctly fails (anchors removed)")
  }
}

console.log("OK: all four anchors unique; patch preserves downstream RPC; idempotent behavior consistent")
