#!/usr/bin/env node
/**
 * Apply + rerun rotating-feed migrations (015/030/10000) on embedded Postgres.
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import EmbeddedPostgres from "embedded-postgres"
import pg from "pg"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../..")
const { Client } = pg

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
  ]) {
    body = body.replaceAll(from, to)
  }
  body = body.replace(
    "from public.trades tx\n                where tx.id = p.trade_id\n                  and coalesce(tx.is_public, false) = true",
    "from public.trades_public_read tx\n                where tx.id = p.trade_id"
  )
  return body
}

async function applySqlFile(client, rel, label) {
  const sql = readRoot(rel)
  process.stdout.write(`  apply ${label} … `)
  await client.query(sql)
  console.log("ok")
}

async function catalog(client) {
  const { rows } = await client.query(`
    select
      p.proname,
      p.oid,
      p.pronargs,
      p.prorettype::regtype as rettype,
      p.prosecdef,
      pg_get_function_identity_arguments(p.oid) as idargs,
      left(pg_get_functiondef(p.oid), 200) as def_prefix
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('rpc_v1_feed_bootstrap', 'rpc_v2_feed_bootstrap')
    order by p.proname, p.oid
  `)
  return rows
}

async function main() {
  const pgdata = path.join(__dirname, ".pgdata-feed-rotating-mig")
  fs.rmSync(pgdata, { recursive: true, force: true })
  const db = new EmbeddedPostgres({ databaseDir: pgdata, port: 55433 })
  await db.initialise()
  await db.start()

  const client = new Client({
    host: "127.0.0.1",
    port: 55433,
    database: "postgres",
    user: "postgres",
    password: "password",
  })
  await client.connect()

  try {
    await client.query(
      `do $$ begin
        create role authenticated;
        create role anon;
      exception when duplicate_object then null;
      end $$`
    )
    for (const init of [
      "supabase/staging/benchmark/init/01_schema.sql",
      "supabase/staging/benchmark/init/02_indexes.sql",
      "supabase/staging/benchmark/init/03_feed_helpers.sql",
      "supabase/staging/benchmark/init/04_feed_rpc_stubs.sql",
    ]) {
      await applySqlFile(client, init, path.basename(init))
    }

    await client.query(`
      create table if not exists auth.users (
        id uuid primary key
      );
    `)

    const body = buildProductionShapedBody()
    await client.query(`
      create or replace function public.get_active_block_peer_ids()
      returns uuid[] language sql stable as $$ select '{}'::uuid[] $$;
    `)
    await client.query(`
      create or replace function public.rpc_v1_feed_bootstrap(
        p_scope text default 'following',
        p_content_filter text default 'all',
        p_limit integer default 8,
        p_cursor text default null
      ) returns jsonb language plpgsql stable set search_path to public
      as $function$ ${body} $function$;
    `)

    console.log("\nBaseline v1:")
    console.table(await catalog(client))

    const probe = await client.query(
      `select pg_get_functiondef(p.oid) as d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='rpc_v1_feed_bootstrap' and p.pronargs=4`
    )
    const def = probe.rows[0]?.d ?? ""
    const sigSnippet = def.slice(0, 500)
    console.log("\nv1 def head:\n", sigSnippet)

    const migrations = [
      "supabase/migrations/20261126001500_feed_content_impressions.sql",
      "supabase/migrations/20261126003000_rpc_v2_feed_bootstrap.sql",
      "supabase/migrations/20261126010000_feed_rotating_rank_v2_hardening.sql",
    ]

    for (let round = 1; round <= 2; round++) {
      console.log(`\n=== migration round ${round} ===`)
      for (const m of migrations) {
        await applySqlFile(client, m, path.basename(m))
      }
      console.log("\nCatalog after round:")
      console.table(await catalog(client))
    }

    const v2 = await client.query(`
      select count(*)::int as n from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='rpc_v2_feed_bootstrap' and p.pronargs=7 and not p.prosecdef
    `)
    if (v2.rows[0].n !== 1) {
      throw new Error(`expected exactly one v2 invoker 7-arg, got ${v2.rows[0].n}`)
    }
    console.log("\nPASS: v2 exists (7 args, invoker), migrations idempotent x2")
  } finally {
    await client.end()
    await db.stop()
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})