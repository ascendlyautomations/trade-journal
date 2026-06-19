/**
 * Validates admin delete API auth via Bearer token (same path as supabaseBearerHeaders).
 * Usage:
 *   node scripts/validate-admin-delete-auth.mjs <targetUserId> <accessToken>
 * Or set ADMIN_TEST_EMAIL + ADMIN_TEST_PASSWORD in .env.local to sign in first.
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
    let val = line.slice(i + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    env[line.slice(0, i).trim()] = val
  }
  return env
}

const env = loadEnv()
const targetUserId = process.argv[2]
let accessToken = process.argv[3]

if (!targetUserId) {
  console.error(
    "Usage: node scripts/validate-admin-delete-auth.mjs <targetUserId> [accessToken]"
  )
  process.exit(1)
}

const baseUrl = process.env.VALIDATE_BASE_URL || "http://localhost:3000"

async function resolveToken() {
  if (accessToken) return accessToken

  const email = env.ADMIN_TEST_EMAIL
  const password = env.ADMIN_TEST_PASSWORD
  if (!email || !password) {
    console.error("Provide accessToken arg or ADMIN_TEST_EMAIL + ADMIN_TEST_PASSWORD in .env.local")
    process.exit(1)
  }

  const sb = createClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  )
  const { data, error } = await sb.auth.signInWithPassword({ email, password })
  if (error || !data.session?.access_token) {
    console.error("Sign-in failed:", error?.message ?? "no session")
    process.exit(1)
  }
  return data.session.access_token
}

async function probe(label, url, init) {
  const res = await fetch(url, init)
  const text = await res.text()
  let body
  try {
    body = JSON.parse(text)
  } catch {
    body = text
  }
  console.log(`\n=== ${label} ===`)
  console.log("status:", res.status)
  console.log("body:", JSON.stringify(body, null, 2))
  return res.status
}

async function main() {
  const token = await resolveToken()
  const authHeaders = { Authorization: `Bearer ${token}` }

  const previewStatus = await probe(
    "GET delete-preview",
    `${baseUrl}/api/admin/users/${targetUserId}/delete-preview`,
    { credentials: "include", headers: { ...authHeaders } }
  )

  const noAuthStatus = await probe(
    "GET delete-preview (no auth — expect 401)",
    `${baseUrl}/api/admin/users/${targetUserId}/delete-preview`,
    {}
  )

  console.log("\n=== SUMMARY ===")
  console.log("preview with bearer:", previewStatus === 200 ? "OK" : `FAIL (${previewStatus})`)
  console.log("preview without auth:", noAuthStatus === 401 ? "OK (401 as expected)" : `unexpected (${noAuthStatus})`)

  if (previewStatus !== 200) process.exit(1)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
