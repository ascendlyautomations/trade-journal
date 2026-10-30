#!/usr/bin/env node
/** Global feed cand parity: legacy single-query vs patched global-only arm (embedded PG). */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import EmbeddedPostgres from "embedded-postgres"
import pg from "pg"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const { Client } = pg

function readSql(rel) {
  return fs.readFileSync(path.join(__dirname, rel), "utf8")
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-global-parity"),
    port: 55433,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()
  const client = new Client({
    host: "127.0.0.1",
    port: 55433,
    user: "postgres",
    password: "password",
    database: "postgres",
  })
  await client.connect()
  try {
    await client.query(
      `do $$ begin create role authenticated; exception when duplicate_object then null; end $$`
    )
    for (const f of ["init/01_schema.sql", "init/02_indexes.sql", "init/03_feed_helpers.sql"]) {
      await client.query(readSql(f))
    }
    await client.query("begin")
    await client.query(`select set_config('bench.scale', 'sparse', true)`)
    await client.query(readSql("seed/seed_synthetic.sql"))
    await client.query("commit")

    const viewer = "cccccccc-cccc-4ccc-8ccc-000000000099"
    await client.query(
      `insert into public.profiles (id, username) values ($1, 'global_viewer') on conflict do nothing`,
      [viewer]
    )

    await client.query("begin")
    await client.query("set local role authenticated")
    await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [viewer])
    await client.query(`
      create temp table _global_ctx on commit drop as
      select
        $1::uuid as v_uid,
        coalesce(
          (select array_agg(f.following_id) from public.followers f where f.follower_id = $1),
          '{}'::uuid[]
        ) as v_following,
        '{}'::uuid[] as v_block_peers,
        9 as lim
    `, [viewer])

    const legacy = await client.query(`
      select p.id, p.created_at from public.posts p, _global_ctx c
      where p.user_id is distinct from c.v_uid
        and not (p.user_id = any (c.v_block_peers))
        and public._v1_feed_before_cursor(p.created_at, 'post', p.id, null,null,null,null,false)
        and (cardinality(c.v_following) = 0 or not (p.user_id = any (c.v_following)))
      order by p.created_at desc, p.id desc limit 9
    `)
    const patchedGlobalArm = await client.query(`
      select p.id, p.created_at from public.posts p, _global_ctx c
      where c.v_uid is not null
        and p.user_id is distinct from c.v_uid
        and not (p.user_id = any (c.v_block_peers))
        and public._v1_feed_before_cursor(p.created_at, 'post', p.id, null,null,null,null,false)
        and (cardinality(c.v_following) = 0 or not (p.user_id = any (c.v_following)))
      order by p.created_at desc, p.id desc limit 9
    `)
    await client.query("rollback")

    const key = (r) => `${r.id}|${r.created_at.toISOString()}`
    const ls = new Set(legacy.rows.map(key))
    const ps = new Set(patchedGlobalArm.rows.map(key))
    let diff = 0
    for (const k of ls) if (!ps.has(k)) diff++
    for (const k of ps) if (!ls.has(k)) diff++
    if (diff !== 0) {
      console.error("FAIL global posts cand parity", diff)
      process.exit(1)
    }
    console.log("OK global posts cand parity (legacy filter vs migration global arm)")
  } finally {
    await client.end()
    await embedded.stop()
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
