#!/usr/bin/env node
/**
 * Phase 1 feed RLS block peers: behavioral parity + EXPLAIN single-eval check.
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import EmbeddedPostgres from "embedded-postgres"
import pg from "pg"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../..")
const { Client } = pg

function read(rel) {
  return fs.readFileSync(path.join(__dirname, rel), "utf8")
}

async function asUser(client, userId, fn) {
  await client.query("begin")
  await client.query("set local role authenticated")
  await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [userId])
  try {
    return await fn()
  } finally {
    await client.query("rollback")
  }
}

async function asGuest(client, fn) {
  await client.query("begin")
  await client.query("set local role anon")
  await client.query(`select set_config('request.jwt.claim.sub', '', true)`)
  try {
    return await fn()
  } finally {
    await client.query("rollback")
  }
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-feed-rls-block-peers"),
    port: 55438,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()

  const client = new Client({
    host: "127.0.0.1",
    port: 55438,
    user: "postgres",
    password: "password",
    database: "postgres",
  })
  await client.connect()

  try {
    await client.query(
      `do $$ begin create role authenticated; exception when duplicate_object then null; end $$`
    )
    await client.query(`do $$ begin create role anon; exception when duplicate_object then null; end $$`)
    for (const f of ["init/01_schema.sql", "init/05_feed_rls_block_peers_test_extras.sql"]) {
      await client.query(read(f))
    }
    for (const stmt of [
      `drop policy if exists posts_select_visible on public.posts`,
      `drop policy if exists profile_posts_select_visible on public.profile_posts`,
      `drop policy if exists achievement_posts_select_visible on public.achievement_posts`,
      `drop policy if exists reels_select_visible on public.reels`,
    ]) {
      await client.query(stmt)
    }
    await client.query(
      fs.readFileSync(
        path.join(root, "supabase/migrations/20261027160000_feed_rls_block_peers_array.sql"),
        "utf8"
      )
    )
    await client.query(`grant select on all tables in schema public to anon, authenticated`)

    const viewer = "aaaaaaaa-aaaa-4aaa-8aaa-000000000001"
    const author = "bbbbbbbb-bbbb-4bbb-8bbb-000000000002"
    const blocked = "cccccccc-cccc-4ccc-8ccc-000000000003"
    for (const [id, name] of [
      [viewer, "viewer"],
      [author, "author"],
      [blocked, "blocked"],
    ]) {
      await client.query(
        `insert into public.profiles (id, username, is_private) values ($1, $2, false)`,
        [id, name]
      )
    }
    await client.query(
      `insert into public.user_blocks (blocker_id, blocked_id) values ($1, $2)`,
      [viewer, blocked]
    )

    const postAuthor = "dddddddd-dddd-4ddd-8ddd-000000000010"
    const postBlocked = "eeeeeeee-eeee-4eee-8eee-000000000011"
    const ppAuthor = "ffffffff-ffff-4fff-8fff-000000000012"
    const ppBlocked = "11111111-1111-4111-8111-000000000013"
    await client.query(
      `insert into public.posts (id, user_id, created_at) values
        ($1, $2, now()), ($3, $4, now())`,
      [postAuthor, author, postBlocked, blocked]
    )
    await client.query(
      `insert into public.profile_posts (id, user_id, content, created_at) values
        ($1, $2, 'ok', now()), ($3, $4, 'blocked', now())`,
      [ppAuthor, author, ppBlocked, blocked]
    )

    // Owner sees own row
    const own = await asUser(client, author, async () => {
      const { rows } = await client.query(
        `select id from public.posts where id = $1`,
        [postAuthor]
      )
      return rows.length
    })
    if (own !== 1) throw new Error("owner must read own post")

    // Viewer sees author (unblocked)
    const seeAuthor = await asUser(client, viewer, async () => {
      const { rows } = await client.query(`select id from public.posts where id = $1`, [
        postAuthor,
      ])
      return rows.length
    })
    if (seeAuthor !== 1) throw new Error("viewer must read unblocked author post")

    const seeAuthorPp = await asUser(client, viewer, async () => {
      const { rows } = await client.query(`select id from public.profile_posts where id = $1`, [
        ppAuthor,
      ])
      return rows.length
    })
    if (seeAuthorPp !== 1) throw new Error("viewer must read unblocked author profile_post (REST)")

    // Feed-shaped scan: same RLS as direct REST
    const feedIds = await asUser(client, viewer, async () => {
      const { rows } = await client.query(
        `select id from public.posts order by created_at desc limit 20`
      )
      return new Set(rows.map((r) => r.id))
    })
    if (!feedIds.has(postAuthor)) throw new Error("feed scan must include unblocked author post")
    if (feedIds.has(postBlocked)) throw new Error("feed scan must exclude blocked peer post")

    // Viewer cannot see blocked peer post (direct REST)
    const seeBlockedPost = await asUser(client, viewer, async () => {
      const { rows } = await client.query(`select id from public.posts where id = $1`, [
        postBlocked,
      ])
      return rows.length
    })
    if (seeBlockedPost !== 0) throw new Error("viewer must not read blocked peer post")

    const seeBlockedPp = await asUser(client, viewer, async () => {
      const { rows } = await client.query(`select id from public.profile_posts where id = $1`, [
        ppBlocked,
      ])
      return rows.length
    })
    if (seeBlockedPp !== 0) throw new Error("profile_posts REST must hide blocked peer")

    // Blocked-by: blocked user cannot see viewer content
    const viewerPost = "22222222-2222-4222-8222-000000000014"
    await client.query(
      `insert into public.posts (id, user_id, created_at) values ($1, $2, now())`,
      [viewerPost, viewer]
    )
    const blockedSeesViewer = await asUser(client, blocked, async () => {
      const { rows } = await client.query(`select id from public.posts where id = $1`, [
        viewerPost,
      ])
      return rows.length
    })
    if (blockedSeesViewer !== 0) throw new Error("blocked-by must hide viewer post")

    // Guest: public author post visible
    const guestSee = await asGuest(client, async () => {
      const { rows } = await client.query(`select id from public.posts where id = $1`, [
        postAuthor,
      ])
      return rows.length
    })
    if (guestSee !== 1) throw new Error("guest must read public author post")

    const guestFeedIds = await asGuest(client, async () => {
      const { rows } = await client.query(
        `select id from public.posts order by created_at desc limit 20`
      )
      return new Set(rows.map((r) => r.id))
    })
    if (!guestFeedIds.has(postAuthor)) throw new Error("guest feed scan must include public post")

    // rls_passes_block_peer_check matches NOT viewer_has_block_with for sample ids
    const { rows: parity } = await asUser(client, viewer, async () =>
      client.query(`
        select
          p.id,
          public.rls_passes_block_peer_check(p.user_id) as rls_ok,
          not public.viewer_has_block_with(p.user_id) as legacy_ok
        from public.posts p
      `)
    )
    for (const r of parity) {
      if (r.rls_ok !== r.legacy_ok) {
        throw new Error(
          `parity mismatch post ${r.id}: rls=${r.rls_ok} legacy=${r.legacy_ok}`
        )
      }
    }

    // Guests must not call get_active_block_peer_ids directly (authenticated-only RPC).
    let anonRpcDenied = false
    try {
      await asGuest(client, async () => {
        await client.query(`select public.get_active_block_peer_ids()`)
      })
    } catch {
      anonRpcDenied = true
    }
    if (!anonRpcDenied) {
      throw new Error("anon must not execute get_active_block_peer_ids directly")
    }

    // EXPLAIN: peer list helper should be planned once (InitPlan), not per row.
    const planRows = await asUser(client, viewer, async () =>
      client.query(`explain (verbose, costs off) select id, user_id from public.posts`)
    )
    const planText = planRows.rows.map((r) => r["QUERY PLAN"]).join("\n")
    if (!/InitPlan.*rls_viewer_block_peer_ids|rls_viewer_block_peer_ids/i.test(planText)) {
      throw new Error(
        `expected rls_viewer_block_peer_ids in EXPLAIN plan\n${planText}`
      )
    }
    const peerListHits = (planText.match(/rls_viewer_block_peer_ids/g) || []).length
    if (peerListHits > 3) {
      throw new Error(
        `expected at most 3 rls_viewer_block_peer_ids refs in EXPLAIN, got ${peerListHits}\n${planText}`
      )
    }

    console.log("OK feed RLS block peers isolated verification passed")
  } finally {
    await client.end()
    await embedded.stop()
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
