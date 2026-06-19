/**
 * Validates legacy follows cleanup in deleteUserAdmin.
 * WARNING: permanently deletes seeded test users.
 */
import { createClient } from "@supabase/supabase-js"
import { randomUUID } from "node:crypto"
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

async function findAdminId() {
  const { data } = await supabase.from("admin_users").select("user_id").limit(1)
  return data?.[0]?.user_id ?? null
}

async function createTestUser(label) {
  const id = randomUUID()
  const email = `follows-cleanup-${label}-${Date.now()}@tradetraxs-test.invalid`
  const password = `Test-${randomUUID().slice(0, 8)}!`

  const { data, error } = await supabase.auth.admin.createUser({
    id,
    email,
    password,
    email_confirm: true,
  })

  if (error || !data.user?.id) {
    throw new Error(`createUser ${label}: ${error?.message ?? "no user"}`)
  }

  await supabase.from("profiles").upsert({
    id: data.user.id,
    username: `follows_${label}_${data.user.id.slice(0, 6)}`,
    updated_at: new Date().toISOString(),
  })

  return data.user.id
}

async function findOtherProfileId(excludeId) {
  const { data } = await supabase
    .from("profiles")
    .select("id")
    .neq("id", excludeId)
    .not("username", "is", null)
    .limit(1)
    .maybeSingle()
  return data?.id ?? null
}

async function countFollows(userId) {
  const { count, error } = await supabase
    .from("follows")
    .select("*", { count: "exact", head: true })
    .or(`follower_id.eq.${userId},following_id.eq.${userId}`)
  if (error) throw new Error(`count follows: ${error.message}`)
  return count ?? 0
}

async function countFollowers(userId) {
  const { count, error } = await supabase
    .from("followers")
    .select("*", { count: "exact", head: true })
    .or(`follower_id.eq.${userId},following_id.eq.${userId}`)
  if (error) throw new Error(`count followers: ${error.message}`)
  return count ?? 0
}

const SCENARIOS = {
  following: async (targetId, otherId) => {
    await supabase.from("follows").insert({
      follower_id: targetId,
      following_id: otherId,
    })
    await supabase.from("followers").insert({
      follower_id: targetId,
      following_id: otherId,
    })
  },
  followed_by: async (targetId, otherId) => {
    await supabase.from("follows").insert({
      follower_id: otherId,
      following_id: targetId,
    })
    await supabase.from("followers").insert({
      follower_id: otherId,
      following_id: targetId,
    })
  },
  both: async (targetId, otherId) => {
    await SCENARIOS.following(targetId, otherId)
    const { data: third } = await supabase
      .from("profiles")
      .select("id")
      .neq("id", targetId)
      .neq("id", otherId)
      .not("username", "is", null)
      .limit(1)
      .maybeSingle()
    if (!third?.id) throw new Error("need third profile for both scenario")
    await supabase.from("follows").insert({
      follower_id: third.id,
      following_id: targetId,
    })
    await supabase.from("followers").insert({
      follower_id: third.id,
      following_id: targetId,
    })
  },
}

async function verifyDeleted(userId) {
  const { data: profile } = await supabase
    .from("profiles")
    .select("id")
    .eq("id", userId)
    .maybeSingle()
  const { data: authData } = await supabase.auth.admin.getUserById(userId)
  const followsLeft = await countFollows(userId)
  const followersLeft = await countFollowers(userId)
  const { data: audit } = await supabase
    .from("admin_audit_log")
    .select("id, action, target_id")
    .eq("target_id", userId)
    .eq("action", "delete_user")
    .order("created_at", { ascending: false })
    .limit(1)

  return {
    profileRemoved: !profile?.id,
    authRemoved: !authData?.user?.id,
    followsLeft,
    followersLeft,
    auditCreated: Boolean(audit?.length),
  }
}

async function main() {
  const adminUserId = await findAdminId()
  if (!adminUserId) {
    console.error("No admin user found")
    process.exit(1)
  }

  const only = process.argv[2]
  const keys = Object.keys(SCENARIOS).filter((k) => !only || k === only)
  const results = []

  for (const scenario of keys) {
    console.log(`\n=== ${scenario} ===`)
    let userId = null
    try {
      userId = await createTestUser(scenario)
      const otherId = await findOtherProfileId(userId)
      if (!otherId) throw new Error("no other profile for follow seed")

      await SCENARIOS[scenario](userId, otherId)
      const followsBefore = await countFollows(userId)
      console.log("seeded follows count:", followsBefore)

      await deleteUserAdmin(supabase, {
        adminUserId,
        targetUserId: userId,
        stripe: null,
      })

      const verification = await verifyDeleted(userId)
      const ok =
        verification.profileRemoved &&
        verification.authRemoved &&
        verification.followsLeft === 0 &&
        verification.followersLeft === 0 &&
        verification.auditCreated

      console.log("verification:", verification)
      results.push({ scenario, ok, verification })
    } catch (err) {
      console.error("FAILED:", err)
      if (userId) {
        try {
          await supabase.auth.admin.deleteUser(userId)
        } catch {
          /* best effort */
        }
      }
      results.push({
        scenario,
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
  process.exit(results.some((r) => !r.ok) ? 1 : 0)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
