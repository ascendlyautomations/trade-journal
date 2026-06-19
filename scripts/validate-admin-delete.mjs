/**
 * Validates deleteUserAdmin against live Supabase test accounts.
 * WARNING: permanently deletes users listed in SCENARIOS.
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
const supabase = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY
)

const { deleteUserAdmin } = await import("../lib/deleteUserAdmin.ts")

const SCENARIOS = [
  {
    label: "participant-only room message",
    userId: "3cc61c07-3216-464f-90a1-369efaea1e36",
    username: "nrltrades123",
  },
  {
    label: "empty account",
    userId: "6673b87f-6114-4898-9ecc-dcf2df62f6fb",
    username: "trialingtest",
  },
  {
    label: "room owner",
    userId: "7849522c-b458-44c0-bed0-0dbc73782658",
    username: "domaintest",
  },
  {
    label: "messages in multiple rooms",
    userId: "e83724f7-7eb5-4ad6-8a2a-56734e142f1f",
    username: "oijdfsoajsdoifjasd",
  },
]

async function findAdminId() {
  const { data } = await supabase.from("admin_users").select("user_id").limit(1)
  return data?.[0]?.user_id ?? null
}

async function verifyDeleted(userId) {
  const { data: profile } = await supabase
    .from("profiles")
    .select("id")
    .eq("id", userId)
    .maybeSingle()
  const { data: authData } = await supabase.auth.admin.getUserById(userId)
  const { data: audit } = await supabase
    .from("admin_audit_log")
    .select("id, action, target_user_id, target_id")
    .eq("target_id", userId)
    .eq("action", "delete_user")
    .order("created_at", { ascending: false })
    .limit(1)

  const checks = [
    ["profile removed", !profile?.id],
    ["auth user removed", !authData?.user?.id],
    ["audit log created", Boolean(audit?.length)],
    ["audit target_user_id preserved", audit?.[0]?.target_user_id === userId],
  ]

  const leftover = []
  for (const [table, col] of [
    ["trades", "user_id"],
    ["posts", "user_id"],
    ["rooms", "owner_user_id"],
    ["notifications", "user_id"],
    ["room_messages", "user_id"],
  ]) {
    const { count } = await supabase
      .from(table)
      .select("*", { count: "exact", head: true })
      .eq(col, userId)
    if ((count ?? 0) > 0) leftover.push(`${table}: ${count}`)
  }

  return { checks, leftover }
}

async function main() {
  const adminUserId = await findAdminId()
  if (!adminUserId) {
    console.error("No admin user found")
    process.exit(1)
  }
  console.log("adminUserId:", adminUserId)

  const only = process.argv[2]
  const scenarios = only
    ? SCENARIOS.filter((s) => s.label.includes(only) || s.userId === only)
    : SCENARIOS

  if (scenarios.length === 0) {
    console.error("No matching scenarios. Pass userId or label filter.")
    process.exit(1)
  }

  const results = []

  for (const scenario of scenarios) {
    console.log(`\n=== ${scenario.label} (${scenario.username}) ===`)
    try {
      const result = await deleteUserAdmin(supabase, {
        adminUserId,
        targetUserId: scenario.userId,
        stripe: null,
      })
      console.log("deleteUserAdmin:", result)
      const verification = await verifyDeleted(scenario.userId)
      console.log("verification:", verification)
      results.push({ scenario: scenario.label, ok: true, verification })
    } catch (err) {
      console.error("FAILED:", err)
      results.push({
        scenario: scenario.label,
        ok: false,
        error:
          err && typeof err === "object"
            ? {
                step: err.step ?? null,
                table: err.table ?? null,
                message: err.message ?? String(err),
              }
            : String(err),
      })
    }
  }

  console.log("\n=== SUMMARY ===")
  console.log(JSON.stringify(results, null, 2))
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
