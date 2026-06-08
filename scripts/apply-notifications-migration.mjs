import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { Client } from "pg"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "..")

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

const LEGACY_BACKFILL_MIGRATION =
  "20260607130000_notifications_post_id_content_legacy_backfill.sql"

const APP_SELECT =
  "id, user_id, sender_id, type, post_id, trade_id, content, read, created_at"

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
  const countRes = await fetch(`${supabaseUrl}/rest/v1/notifications?select=id`, {
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      Prefer: "count=exact",
    },
  })
  const total = countRes.headers.get("content-range")?.split("/")?.[1] ?? "?"

  const columns = ["post_id", "content", "message", "read"]
  const columnStatus = {}
  for (const column of columns) {
    const res = await fetch(
      `${supabaseUrl}/rest/v1/notifications?select=${column}&limit=0`,
      {
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
        },
      }
    )
    columnStatus[column] = res.ok ? "exists" : (await res.json()).message
  }

  const appSelectRes = await fetch(
    `${supabaseUrl}/rest/v1/notifications?select=${encodeURIComponent(APP_SELECT)}&limit=1`,
    {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
      },
    }
  )
  const appSelectBody = appSelectRes.ok
    ? JSON.stringify(await appSelectRes.json())
    : JSON.stringify(await appSelectRes.json())

  const anonRes = await fetch(
    `${supabaseUrl}/rest/v1/notifications?select=id&limit=1`,
    {
      headers: {
        apikey: loadEnv().NEXT_PUBLIC_SUPABASE_ANON_KEY,
        Authorization: `Bearer ${loadEnv().NEXT_PUBLIC_SUPABASE_ANON_KEY}`,
      },
    }
  )
  const anonRows = anonRes.ok ? await anonRes.json() : await anonRes.json()

  const sampleRes = await fetch(
    `${supabaseUrl}/rest/v1/notifications?select=id,type,message,content,post_id,trade_id,read&limit=3`,
    {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
      },
    }
  )
  const sampleRows = sampleRes.ok ? await sampleRes.json() : []

  return {
    total,
    columnStatus,
    appSelectStatus: appSelectRes.status,
    appSelectBody: appSelectBody.slice(0, 500),
    anonStatus: anonRes.status,
    anonRowCount: Array.isArray(anonRows) ? anonRows.length : anonRows,
    sampleRows,
  }
}

async function verifyMarkRead(supabaseUrl, serviceRoleKey, userId) {
  const unreadRes = await fetch(
    `${supabaseUrl}/rest/v1/notifications?select=id&user_id=eq.${userId}&read=eq.false&limit=1`,
    {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        Prefer: "count=exact",
      },
    }
  )
  const unreadBefore =
    unreadRes.headers.get("content-range")?.split("/")?.[1] ?? "?"

  const markRes = await fetch(
    `${supabaseUrl}/rest/v1/notifications?user_id=eq.${userId}&read=eq.false`,
    {
      method: "PATCH",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify({ read: true }),
    }
  )
  const marked = markRes.ok ? await markRes.json() : await markRes.json()

  const unreadAfterRes = await fetch(
    `${supabaseUrl}/rest/v1/notifications?select=id&user_id=eq.${userId}&read=eq.false&limit=1`,
    {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        Prefer: "count=exact",
      },
    }
  )
  const unreadAfter =
    unreadAfterRes.headers.get("content-range")?.split("/")?.[1] ?? "?"

  if (Array.isArray(marked) && marked.length > 0) {
    const ids = marked.map((row) => row.id).join(",")
    await fetch(
      `${supabaseUrl}/rest/v1/notifications?id=in.(${ids})`,
      {
        method: "PATCH",
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ read: false }),
      }
    )
  }

  return {
    unreadBefore,
    markStatus: markRes.status,
    markedCount: Array.isArray(marked) ? marked.length : 0,
    unreadAfter,
    restored: Array.isArray(marked) && marked.length > 0,
  }
}

async function main() {
  const env = loadEnv()
  const ref = env.NEXT_PUBLIC_SUPABASE_URL.match(/https:\/\/([^.]+)/)?.[1]
  if (!ref) {
    throw new Error("Could not parse project ref from NEXT_PUBLIC_SUPABASE_URL")
  }

  const migrationSql = loadMigrationSql(LEGACY_BACKFILL_MIGRATION)

  console.log("[migration] before:")
  console.log(JSON.stringify(await restProbe(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY), null, 2))

  const accessToken = env.SUPABASE_ACCESS_TOKEN
  const dbUrl =
    env.DATABASE_URL ||
    (env.SUPABASE_DB_PASSWORD
      ? `postgresql://postgres.${ref}:${encodeURIComponent(env.SUPABASE_DB_PASSWORD)}@aws-1-us-east-2.pooler.supabase.com:6543/postgres`
      : null)

  if (accessToken) {
    console.log("[migration] applying via Supabase Management API...")
    await runViaManagementApi(accessToken, ref, migrationSql)
  } else if (dbUrl) {
    console.log("[migration] applying via postgres pooler...")
    await runViaPg(dbUrl, migrationSql)
  } else {
    throw new Error(
      "Add SUPABASE_ACCESS_TOKEN or SUPABASE_DB_PASSWORD (or DATABASE_URL) to .env.local, then re-run: node scripts/apply-notifications-migration.mjs"
    )
  }

  console.log("[migration] after:")
  const after = await restProbe(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY
  )
  console.log(JSON.stringify(after, null, 2))

  const sampleUserId = after.sampleRows?.[0]?.id
    ? (
        await fetch(
          `${env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/notifications?select=user_id&limit=1`,
          {
            headers: {
              apikey: env.SUPABASE_SERVICE_ROLE_KEY,
              Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
            },
          }
        ).then((res) => res.json())
      )?.[0]?.user_id
    : null

  if (sampleUserId) {
    console.log("[migration] mark-read probe:")
    console.log(
      JSON.stringify(
        await verifyMarkRead(
          env.NEXT_PUBLIC_SUPABASE_URL,
          env.SUPABASE_SERVICE_ROLE_KEY,
          sampleUserId
        ),
        null,
        2
      )
    )
  }
}

main().catch((error) => {
  console.error("[migration] failed:", error.message)
  process.exit(1)
})
