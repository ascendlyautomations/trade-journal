#!/usr/bin/env node
/**
 * Writes rollback SQL restoring pre-20261027140000 rpc_v1_feed_bootstrap (production-shaped baseline).
 * Cross-check: production pg_get_functiondef on fobudrkniacatvilbofw (2026-10-27) must match anchors.
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
  const exploreSql = readRoot(
    "supabase/migrations/20260915230000_explore_mode_guest_security_hardening.sql"
  )
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

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-export-rollback"),
    port: 55436,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()
  const client = new Client({
    host: "127.0.0.1",
    port: 55436,
    user: "postgres",
    password: "password",
    database: "postgres",
  })
  await client.connect()
  try {
    await client.query(
      `do $$ begin create role authenticated; exception when duplicate_object then null; end $$`
    )
    for (const f of ["init/01_schema.sql", "init/03_feed_helpers.sql", "init/04_feed_rpc_stubs.sql"]) {
      await client.query(fs.readFileSync(path.join(__dirname, f), "utf8"))
    }
    const body = buildProductionShapedBody()
    await client.query(`
CREATE OR REPLACE FUNCTION public.rpc_v1_feed_bootstrap(
  p_scope text DEFAULT 'following',
  p_content_filter text DEFAULT 'all',
  p_limit integer DEFAULT 8,
  p_cursor text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO public AS $function$ ${body} $function$;`)

    const { rows } = await client.query(`
      select pg_get_functiondef(p.oid) as def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'rpc_v1_feed_bootstrap'
        and pg_get_function_identity_arguments(p.oid) =
          'p_scope text, p_content_filter text, p_limit integer, p_cursor text'
    `)
    const def = rows[0].def
    if (def.includes("post_merge")) throw new Error("baseline must not include post_merge")
    if (!def.includes("get_active_block_peer_ids()")) throw new Error("missing block peers")

    const outPath = path.join(
      root,
      "supabase/migrations/rollback/20261027140000_feed_following_cand_per_followee_rollback.sql"
    )
    const header = `-- Rollback: restore pre-20261027140000 Following cand (per-followee LATERAL) RPC body.
-- Source: production pg_get_functiondef equivalent on fobudrkniacatvilbofw (2026-10-27 read-only verify).
-- Apply manually on staging/production only after controlled rollback decision — not auto-run.

`
    const footer = `
comment on function public.rpc_v1_feed_bootstrap(text, text, integer, text) is
  'Backend V2 Feed bootstrap — excludes blocked authors via get_active_block_peer_ids (bidirectional user_blocks).';
`
    fs.mkdirSync(path.dirname(outPath), { recursive: true })
    let ddl = def.trim().replace(/end;\s+\$function\$/, "end;\n$function$;")
    if (!ddl.endsWith(";")) ddl += ";"
    fs.writeFileSync(outPath, header + ddl + "\n" + footer)
    console.log("Wrote", outPath, "bytes", fs.statSync(outPath).size)
  } finally {
    await client.end()
    await embedded.stop()
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
