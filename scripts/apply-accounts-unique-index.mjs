/**
 * Apply accounts unique index migration after duplicate cleanup.
 *
 * Usage: node scripts/apply-accounts-unique-index.mjs
 *
 * Requires SUPABASE_ACCESS_TOKEN or SUPABASE_DB_PASSWORD (or DATABASE_URL) in .env.local
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { Client } from "pg"
import { createClient } from "@supabase/supabase-js"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "..")
const MIGRATION = "20260616130000_accounts_user_name_unique.sql"

function loadEnv() {
  const text = fs.readFileSync(path.join(root, ".env.local"), "utf8")
  return Object.fromEntries(
    text
      .split(/\r?\n/)
      .filter((line) => line && !line.startsWith("#"))
      .map((line) => {
        const index = line.indexOf("=")
        return [line.slice(0, index), line.slice(index + 1)]
      })
  )
}

function loadMigrationSql(filename) {
  return fs.readFileSync(
    path.join(root, "supabase", "migrations", filename),
    "utf8"
  )
}

async function runViaManagementApi(accessToken, ref, sql) {
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${ref}/database/query`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query: sql }),
    }
  )
  const body = await response.text()
  if (!response.ok) {
    throw new Error(`Management API ${response.status}: ${body}`)
  }
  return body
}

async function runViaPg(connectionString, sql) {
  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
  })
  await client.connect()
  try {
    await client.query(sql)
  } finally {
    await client.end()
  }
}

async function probeDuplicates(supabase) {
  const { data, error } = await supabase
    .from("accounts")
    .select("id,user_id,name,created_at")
  if (error) throw error
  const groups = new Map()
  for (const row of data ?? []) {
    const key = `${row.user_id}::${String(row.name ?? "").trim().toLowerCase()}`
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push(row)
  }
  return [...groups.values()].filter((rows) => rows.length > 1).length
}

async function probeIndex(pgClient) {
  const res = await pgClient.query(
    `select indexname from pg_indexes where schemaname = 'public' and indexname = 'accounts_user_id_name_unique_idx'`
  )
  return res.rows.length > 0
}

async function main() {
  const env = loadEnv()
  const ref = env.NEXT_PUBLIC_SUPABASE_URL.match(/https:\/\/([^.]+)/)?.[1]
  if (!ref) throw new Error("Could not parse project ref")

  const supabase = createClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { autoRefreshToken: false, persistSession: false } }
  )

  const dupGroups = await probeDuplicates(supabase)
  console.log("[index] duplicate groups before apply:", dupGroups)
  if (dupGroups > 0) {
    throw new Error(
      `Still ${dupGroups} duplicate group(s). Run: node scripts/cleanup-duplicate-accounts.mjs --apply`
    )
  }

  const sql = loadMigrationSql(MIGRATION)
  const accessToken = env.SUPABASE_ACCESS_TOKEN
  const dbUrl =
    env.DATABASE_URL ||
    (env.SUPABASE_DB_PASSWORD
      ? `postgresql://postgres.${ref}:${encodeURIComponent(env.SUPABASE_DB_PASSWORD)}@aws-1-us-east-2.pooler.supabase.com:6543/postgres`
      : null)

  if (accessToken) {
    console.log("[index] applying via Supabase Management API...")
    await runViaManagementApi(accessToken, ref, sql)
  } else if (dbUrl) {
    console.log("[index] applying via postgres pooler...")
    await runViaPg(dbUrl, sql)
  } else {
    throw new Error(
      "Add SUPABASE_ACCESS_TOKEN or SUPABASE_DB_PASSWORD (or DATABASE_URL) to .env.local"
    )
  }

  if (dbUrl) {
    const client = new Client({
      connectionString: dbUrl,
      ssl: { rejectUnauthorized: false },
    })
    await client.connect()
    try {
      const exists = await probeIndex(client)
      console.log("[index] accounts_user_id_name_unique_idx exists:", exists)
    } finally {
      await client.end()
    }
  }

  console.log("[index] migration applied successfully")
}

main().catch((err) => {
  console.error("[index] failed:", err.message)
  process.exit(1)
})
