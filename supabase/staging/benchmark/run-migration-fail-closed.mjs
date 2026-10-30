#!/usr/bin/env node
/** Verifies migration fails closed when prerequisites/anchors are missing. */
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

function buildBody() {
  const explore = fs.readFileSync(
    path.join(root, "supabase/migrations/20260915230000_explore_mode_guest_security_hardening.sql"),
    "utf8"
  )
  const start = explore.indexOf("create or replace function public.rpc_v1_feed_bootstrap(")
  const bodyStart = explore.indexOf("as $$\n", start)
  const bodyEnd = explore.indexOf("\n$$;", bodyStart)
  return explore.slice(bodyStart + "as $$\n".length, bodyEnd)
}

async function expectMigrationFail(client, migrationSql, needle) {
  try {
    await client.query(migrationSql)
  } catch (e) {
    if (String(e.message).includes(needle)) return
    throw e
  }
  throw new Error(`expected failure containing: ${needle}`)
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-migration-fail"),
    port: 55435,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()
  const client = new Client({
    host: "127.0.0.1",
    port: 55435,
    user: "postgres",
    password: "password",
    database: "postgres",
  })
  await client.connect()
  const migrationSql = fs.readFileSync(
    path.join(root, "supabase/migrations/20261027140000_feed_following_cand_per_followee.sql"),
    "utf8"
  )
  try {
    await client.query(
      `do $$ begin create role authenticated; exception when duplicate_object then null; end $$`
    )
    for (const f of ["init/01_schema.sql", "init/02_indexes.sql", "init/03_feed_helpers.sql", "init/04_feed_rpc_stubs.sql"]) {
      await client.query(read(f))
    }
    const body = buildBody()
    await client.query(`
CREATE OR REPLACE FUNCTION public.rpc_v1_feed_bootstrap(p_scope text, p_content_filter text, p_limit integer, p_cursor text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $function$ ${body} $function$;`)
    await expectMigrationFail(client, migrationSql, "get_active_block_peer_ids")
    console.log("OK fail-closed: missing block peers prerequisite")
  } finally {
    await client.end()
    await embedded.stop()
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
