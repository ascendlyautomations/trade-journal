import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { Client } from "pg"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "..")

const MIGRATIONS = [
  "20260703140000_user_reviews.sql",
  "20260703150000_user_reviews_public_avatar_fallback.sql",
]

const USER_REVIEW_SELECT =
  "id, user_id, rating, title, review, would_recommend, status, featured, display_name, username_snapshot, avatar_snapshot, version, created_at, updated_at"

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

async function restProbe(supabaseUrl, serviceRoleKey) {
  async function probe(label, path, init = {}) {
    const res = await fetch(`${supabaseUrl}${path}`, {
      ...init,
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        ...(init.headers ?? {}),
      },
    })
    const body = await res.text()
    return {
      label,
      status: res.status,
      body: body.slice(0, 400),
    }
  }

  return [
    await probe("beta_testimonials", "/rest/v1/beta_testimonials?select=id&limit=1"),
    await probe("user_reviews", "/rest/v1/user_reviews?select=id&limit=1"),
    await probe(
      "user_reviews columns",
      `/rest/v1/user_reviews?select=${encodeURIComponent(USER_REVIEW_SELECT)}&limit=0`
    ),
    await probe("list_public_user_reviews rpc", "/rest/v1/rpc/list_public_user_reviews", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    }),
  ]
}

async function main() {
  const env = loadEnv()
  const ref = env.NEXT_PUBLIC_SUPABASE_URL.match(/https:\/\/([^.]+)/)?.[1]
  if (!ref) {
    throw new Error("Could not parse project ref from NEXT_PUBLIC_SUPABASE_URL")
  }

  console.log("[user-reviews migration] before:")
  console.log(
    JSON.stringify(
      await restProbe(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY),
      null,
      2
    )
  )

  const sql = MIGRATIONS.map(loadMigrationSql).join("\n\n")

  const accessToken = env.SUPABASE_ACCESS_TOKEN
  const dbUrl =
    env.DATABASE_URL ||
    (env.SUPABASE_DB_PASSWORD
      ? `postgresql://postgres.${ref}:${encodeURIComponent(env.SUPABASE_DB_PASSWORD)}@aws-1-us-east-2.pooler.supabase.com:6543/postgres`
      : null)

  if (accessToken) {
    console.log("[user-reviews migration] applying via Supabase Management API...")
    await runViaManagementApi(accessToken, ref, sql)
  } else if (dbUrl) {
    console.log("[user-reviews migration] applying via postgres pooler...")
    await runViaPg(dbUrl, sql)
  } else {
    throw new Error(
      "Add SUPABASE_ACCESS_TOKEN or SUPABASE_DB_PASSWORD (or DATABASE_URL) to .env.local, then re-run: node scripts/apply-user-reviews-migration.mjs"
    )
  }

  console.log("[user-reviews migration] after:")
  console.log(
    JSON.stringify(
      await restProbe(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY),
      null,
      2
    )
  )
}

main().catch((error) => {
  console.error("[user-reviews migration] failed:", error.message)
  process.exit(1)
})
