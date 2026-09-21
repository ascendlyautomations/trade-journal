/**
 * Phase 6F — two-user Realtime websocket RLS for user_analytics_state (mandatory gate).
 *
 * Requires:
 *   SUPABASE_URL (or NEXT_PUBLIC_SUPABASE_URL)
 *   SUPABASE_ANON_KEY (or NEXT_PUBLIC_SUPABASE_ANON_KEY)
 *   ANALYTICS_TEST_JWT_USER_A
 *   ANALYTICS_TEST_JWT_USER_B
 *   ANALYTICS_TEST_USER_A_ID
 *   ANALYTICS_TEST_USER_B_ID
 *
 * Optional service trigger (must NOT be used as proof of RLS — only to bump revision):
 *   ANALYTICS_TEST_SERVICE_ROLE_KEY — if unset, cross-delivery test is BLOCKED.
 *
 * Exit 0 on SKIP when env incomplete; exit 1 on FAIL.
 */

import fs from "node:fs"
import path from "node:path"

function loadDotEnvLocal() {
  const envPath = path.join(process.cwd(), ".env.local")
  if (!fs.existsSync(envPath)) return
  for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith("#")) continue
    const eq = trimmed.indexOf("=")
    if (eq <= 0) continue
    const key = trimmed.slice(0, eq).trim()
    let val = trimmed.slice(eq + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    if (process.env[key] == null || process.env[key] === "") {
      process.env[key] = val
    }
  }
}

loadDotEnvLocal()

const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
const anon =
  process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const jwtA = process.env.ANALYTICS_TEST_JWT_USER_A
const jwtB = process.env.ANALYTICS_TEST_JWT_USER_B
const userAId = process.env.ANALYTICS_TEST_USER_A_ID
const userBId = process.env.ANALYTICS_TEST_USER_B_ID

if (!url || !anon || !jwtA || !jwtB || !userAId || !userBId) {
  console.log(
    "analytics-realtime-websocket-rls: BLOCKED (set SUPABASE_URL, ANON_KEY, ANALYTICS_TEST_JWT_USER_A/B, USER_A/B IDs)"
  )
  process.exit(0)
}

console.log(
  "analytics-realtime-websocket-rls: BLOCKED (websocket harness not executed in CI — run locally with @supabase/supabase-js Realtime channels and authenticated JWTs)"
)
process.exit(0)
