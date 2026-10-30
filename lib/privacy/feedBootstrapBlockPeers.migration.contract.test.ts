import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"

const migrationPath = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../supabase/migrations/20261027120000_feed_bootstrap_block_peers_once.sql"
)

describe("feed bootstrap block peers once", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("loads block peers once and filters cand with array membership", () => {
    assert.match(sql, /v_block_peers uuid\[\]/)
    assert.match(sql, /get_active_block_peer_ids\(\)/)
    assert.match(sql, /v_guest or not \(p\.user_id = any \(v_block_peers\)\)/)
    assert.match(sql, /v_guest or not \(pp\.user_id = any \(v_block_peers\)\)/)
    assert.match(sql, /v_guest or not \(ap\.user_id = any \(v_block_peers\)\)/)
    assert.match(sql, /v_guest or not \(r\.user_id = any \(v_block_peers\)\)/)
    assert.match(sql, /v_guest or not \(s\.user_id = any \(v_block_peers\)\)/)
  })

  it("guards invoker and per-row block checks in DO patch", () => {
    assert.match(sql, /still uses per-row users_have_active_block/)
    assert.match(sql, /rpc_v1_feed_bootstrap must stay security invoker/)
    assert.match(sql, /expected 5 per-row block checks/)
    assert.match(sql, /following-load anchor not found/)
    assert.match(sql, /v_block_peers declare patch failed/)
    assert.match(sql, /block peer load patch failed/)
  })

  it("indexes blocker_id for get_active_block_peer_ids blocker branch", () => {
    assert.match(sql, /user_blocks_blocker_id_idx/)
    assert.match(sql, /on public\.user_blocks \(blocker_id\)/)
  })

  it("patch anchors match latest full rpc_v1_feed_bootstrap body in migrations", () => {
    const explorePath = path.join(
      path.dirname(fileURLToPath(import.meta.url)),
      "../../supabase/migrations/20260915230000_explore_mode_guest_security_hardening.sql"
    )
    const exploreSql = fs.readFileSync(explorePath, "utf8")
    const start = exploreSql.indexOf("create or replace function public.rpc_v1_feed_bootstrap(")
    assert.ok(start >= 0)
    const bodyStart = exploreSql.indexOf("as $$\n", start)
    const bodyEnd = exploreSql.indexOf("\n$$;", bodyStart)
    const body = exploreSql.slice(bodyStart + "as $$\n".length, bodyEnd)

    let updated = body
    updated = updated.replace(
      "v_following uuid[] := '{}'::uuid[];",
      "v_following uuid[] := '{}'::uuid[];\n  v_block_peers uuid[] := '{}'::uuid[];"
    )
    updated = updated.replace(
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
      [
        "and not public.users_have_active_block(v_uid, p.user_id)",
        "and (v_guest or not (p.user_id = any (v_block_peers)))",
      ],
      [
        "and not public.users_have_active_block(v_uid, pp.user_id)",
        "and (v_guest or not (pp.user_id = any (v_block_peers)))",
      ],
      [
        "and not public.users_have_active_block(v_uid, ap.user_id)",
        "and (v_guest or not (ap.user_id = any (v_block_peers)))",
      ],
      [
        "and not public.users_have_active_block(v_uid, r.user_id)",
        "and (v_guest or not (r.user_id = any (v_block_peers)))",
      ],
      [
        "or not public.users_have_active_block(v_uid, s.user_id)",
        "or v_guest or not (s.user_id = any (v_block_peers))",
      ],
    ] as const) {
      updated = updated.replaceAll(from, to)
    }

    assert.notEqual(updated, body)
    assert.doesNotMatch(updated, /users_have_active_block\(v_uid,/)
    assert.match(updated, /get_active_block_peer_ids\(\)/)
  })
})
