#!/usr/bin/env node
/**
 * Applies 20261027140000 DO migration on embedded Postgres using production-shaped RPC baseline.
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

function readRoot(rel) {
  return fs.readFileSync(path.join(root, rel), "utf8")
}

function buildProductionShapedBody() {
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

function installBaselineRpc(client, body) {
  const sql = `
CREATE OR REPLACE FUNCTION public.rpc_v1_feed_bootstrap(
  p_scope text DEFAULT 'following',
  p_content_filter text DEFAULT 'all',
  p_limit integer DEFAULT 8,
  p_cursor text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO public
AS $function$
${body}
$function$;
`
  return client.query(sql)
}

async function rpcAs(client, viewerId, scope, cursor) {
  await client.query("begin")
  await client.query("set local role authenticated")
  await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [viewerId])
  const { rows } = await client.query(
    `select public.rpc_v1_feed_bootstrap($1, 'all', 8, $2) as j`,
    [scope, cursor]
  )
  await client.query("rollback")
  return rows[0].j
}

function itemIds(j) {
  return (j.data?.items ?? []).map((it) => `${it.kind}:${it.id}`)
}

function assertJsonContract(j) {
  const required = ["meta", "data"]
  const dataKeys = [
    "scope",
    "content_filter",
    "items",
    "authors",
    "engagement",
    "stories",
    "story_authors",
    "next_cursor",
    "page_meta",
    "following_ids_echo",
  ]
  for (const k of required) {
    if (j[k] == null) throw new Error(`missing ${k}`)
  }
  for (const k of dataKeys) {
    if (j.data[k] === undefined) throw new Error(`missing data.${k}`)
  }
  if (j.meta.contract_version !== "v1") throw new Error("contract_version")
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-migration-do"),
    port: 55434,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()

  const client = new Client({
    host: "127.0.0.1",
    port: 55434,
    user: "postgres",
    password: "password",
    database: "postgres",
  })
  await client.connect()

  const migrationSql = readRoot(
    "supabase/migrations/20261027140000_feed_following_cand_per_followee.sql"
  )
  const body = buildProductionShapedBody()

  try {
    await client.query(
      `do $$ begin create role authenticated; exception when duplicate_object then null; end $$`
    )
    for (const f of [
      "init/01_schema.sql",
      "init/02_indexes.sql",
      "init/03_feed_helpers.sql",
      "init/04_feed_rpc_stubs.sql",
    ]) {
      await client.query(read(f))
    }

    await client.query("begin")
    await client.query(`select set_config('bench.scale', 'sparse', true)`)
    await client.query(read("seed/seed_synthetic.sql"))
    await client.query("commit")

    await installBaselineRpc(client, body)

    const { rows: inv1 } = await client.query(`
      select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='rpc_v1_feed_bootstrap'`)
    if (inv1[0]?.prosecdef) throw new Error("baseline must be security invoker")

    const viewer15 = "aaaaaaaa-aaaa-4aaa-8aaa-000000000015"
    const viewerGlobal = "cccccccc-cccc-4ccc-8ccc-000000000099"
    await client.query(
      `insert into public.profiles (id, username) values ($1, 'g') on conflict do nothing`,
      [viewerGlobal]
    )

    const beforeFollowing = await rpcAs(client, viewer15, "following", null)
    const beforeGlobal = await rpcAs(client, viewerGlobal, "global", null)
    assertJsonContract(beforeFollowing)
    assertJsonContract(beforeGlobal)

    await client.query(migrationSql)

    const { rows: inv2 } = await client.query(`
      select position('post_merge' in pg_get_functiondef(p.oid)) > 0 as patched, p.prosecdef
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='rpc_v1_feed_bootstrap'`)
    if (!inv2[0]?.patched) throw new Error("migration did not apply post_merge")
    if (inv2[0]?.prosecdef) throw new Error("patched RPC must stay security invoker")

    const defAfterFirst = (
      await client.query(
        `select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='rpc_v1_feed_bootstrap'`
      )
    ).rows[0].d

    await client.query(migrationSql)

    const defAfterSecond = (
      await client.query(
        `select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='rpc_v1_feed_bootstrap'`
      )
    ).rows[0].d
    if (defAfterFirst !== defAfterSecond) {
      throw new Error("second migration apply changed function definition")
    }

    const afterFollowing = await rpcAs(client, viewer15, "following", null)
    const afterGlobal = await rpcAs(client, viewerGlobal, "global", null)
    assertJsonContract(afterFollowing)

    const idsBefore = itemIds(beforeFollowing)
    const idsAfter = itemIds(afterFollowing)
    if (JSON.stringify(idsBefore) !== JSON.stringify(idsAfter)) {
      throw new Error(
        `following item ids differ before/after migration: ${JSON.stringify(idsBefore)} vs ${JSON.stringify(idsAfter)}`
      )
    }
    if (beforeFollowing.data.page_meta?.has_more !== afterFollowing.data.page_meta?.has_more) {
      throw new Error("following has_more mismatch")
    }

    const cursor = afterFollowing.data.next_cursor
    if (cursor) {
      const page2 = await rpcAs(client, viewer15, "following", cursor)
      assertJsonContract(page2)
    }

    const blockViewer = "bbbbbbbb-bbbb-4bbb-8bbb-000000000002"
    const blocked = await rpcAs(client, blockViewer, "following", null)
    const blockedAuthor = "00000000-0000-4000-8000-000000000001"
    if (itemIds(blocked).some((x) => x.endsWith(blockedAuthor))) {
      throw new Error("blocked author visible in feed")
    }

    if (JSON.stringify(itemIds(beforeGlobal)) !== JSON.stringify(itemIds(afterGlobal))) {
      throw new Error("global feed item ids changed after migration")
    }

    const rollbackSql = readRoot(
      "supabase/migrations/rollback/20261027140000_feed_following_cand_per_followee_rollback.sql"
    )
    await client.query(rollbackSql)
    const { rows: rolledBack } = await client.query(`
      select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='rpc_v1_feed_bootstrap'`)
    if (rolledBack[0].d.includes("post_merge")) {
      throw new Error("rollback still contains post_merge")
    }
    const afterRollback = await rpcAs(client, viewer15, "following", null)
    if (JSON.stringify(idsBefore) !== JSON.stringify(itemIds(afterRollback))) {
      throw new Error("following ids differ after rollback")
    }

    console.log("OK migration DO-block isolated verification passed")
  } finally {
    await client.end()
    await embedded.stop()
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
