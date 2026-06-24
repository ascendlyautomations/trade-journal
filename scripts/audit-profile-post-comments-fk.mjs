/**
 * Read-only audit: profile_post_comments schema + FK vs trade_comments.
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

function loadEnv() {
  const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
  const env = {}
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue
    const i = line.indexOf("=")
    if (i < 1) continue
    const key = line.slice(0, i).trim()
    let val = line.slice(i + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    env[key] = val
  }
  return env
}

const env = loadEnv()
const url = env.NEXT_PUBLIC_SUPABASE_URL
const key = env.SUPABASE_SERVICE_ROLE_KEY
const supabase = createClient(url, key)

const TABLES = ["profile_post_comments", "trade_comments", "comments"]

async function probeSelect(table, select) {
  const { data, error } = await supabase
    .from(table)
    .select(select)
    .limit(1)
  return { table, select, ok: !error, error: error ?? null, sample: data?.[0] ?? null }
}

async function queryViaManagementApi(env) {
  const token = env.SUPABASE_ACCESS_TOKEN
  const ref = env.NEXT_PUBLIC_SUPABASE_URL?.match(/https:\/\/([^.]+)/)?.[1]
  if (!token || !ref) return null

  const query = `
    select
      c.conname as fk_name,
      cl.relname as table_name,
      a.attname as column_name,
      nf.nspname as ref_schema,
      cf.relname as referenced_table,
      af.attname as referenced_column
    from pg_constraint c
    join pg_class cl on cl.oid = c.conrelid
    join pg_namespace n on n.oid = cl.relnamespace
    join pg_attribute a
      on a.attrelid = c.conrelid and a.attnum = any(c.conkey) and not a.attisdropped
    join pg_class cf on cf.oid = c.confrelid
    join pg_namespace nf on nf.oid = cf.relnamespace
    join pg_attribute af
      on af.attrelid = c.confrelid and af.attnum = any(c.confkey) and not a.attisdropped
    where n.nspname = 'public'
      and c.contype = 'f'
      and cl.relname in (
        'profile_post_comments',
        'trade_comments',
        'comments',
        'profile_post_likes',
        'trade_likes',
        'likes'
      )
    order by cl.relname, c.conname
  `

  const response = await fetch(
    `https://api.supabase.com/v1/projects/${ref}/database/query`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query }),
    }
  )

  const body = await response.text()
  if (!response.ok) {
    console.log("Management API error:", response.status, body)
    return null
  }

  return JSON.parse(body)
}

async function queryLiveSchema() {
  return null
}

async function main() {
  const selects = {
    profile_post_comments:
      "id, profile_post_id, user_id, content, created_at, profiles(username, avatar_url)",
    trade_comments: "*, profiles(username, avatar_url)",
    comments:
      "id, post_id, user_id, content, created_at, profiles(username, avatar_url)",
  }

  console.log("=== PostgREST embed probes (limit 1) ===\n")
  for (const table of TABLES) {
    const result = await probeSelect(table, selects[table])
    console.log(JSON.stringify(result, null, 2))
    console.log("")
  }

  // List columns via a known row or empty select
  console.log("=== Column list probes ===\n")
  for (const table of TABLES) {
    const { data, error } = await supabase.from(table).select("*").limit(1)
    console.log(
      table,
      error ? { error } : { columns: data?.[0] ? Object.keys(data[0]) : "(empty table)" }
    )
  }

  const live = await queryViaManagementApi(env)
  if (!live) {
    console.log(
      "\n=== Live PG schema: skipped (no DATABASE_URL / SUPABASE_DB_PASSWORD / SUPABASE_ACCESS_TOKEN) ==="
    )
    return
  }

  if (live.columns && live.foreignKeys) {
    console.log("\n=== Live columns (information_schema) ===\n")
    console.log(JSON.stringify(live.columns, null, 2))
    console.log("\n=== Live foreign keys (pg_constraint) ===\n")
    console.log(JSON.stringify(live.foreignKeys, null, 2))
    return
  }

  console.log("\n=== Live foreign keys (management API) ===\n")
  console.log(JSON.stringify(live, null, 2))
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
