/**
 * Beta cleanup validation — creates disposable users, seeds data, runs deleteUserAdmin.
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

const REFERENCE_TABLES = [
  ["profiles", "id"],
  ["trades", "user_id"],
  ["posts", "user_id"],
  ["likes", "user_id"],
  ["comments", "user_id"],
  ["room_messages", "user_id"],
  ["rooms", "owner_user_id"],
  ["notifications", "user_id"],
  ["followers", "follower_id"],
  ["followers", "following_id"],
]

async function findAdminId() {
  const { data } = await supabase.from("admin_users").select("user_id").limit(1)
  return data?.[0]?.user_id ?? null
}

async function createTestUser(label) {
  const id = randomUUID()
  const email = `beta-cleanup-${label}-${Date.now()}@tradetraxs-test.invalid`
  const password = `Test-${randomUUID().slice(0, 8)}!`

  const { data, error } = await supabase.auth.admin.createUser({
    id,
    email,
    password,
    email_confirm: true,
    user_metadata: { username: `beta_${label}_${Date.now()}` },
  })

  if (error || !data.user?.id) {
    throw new Error(`createUser ${label}: ${error?.message ?? "no user"}`)
  }

  const userId = data.user.id

  await supabase.from("profiles").upsert({
    id: userId,
    username: `beta_${label}_${userId.slice(0, 6)}`,
    updated_at: new Date().toISOString(),
  })

  return { userId, email }
}

async function findAnyPostId() {
  const { data } = await supabase.from("posts").select("id").limit(1).maybeSingle()
  return data?.id ?? null
}

async function findAnyRoomId() {
  const { data } = await supabase.from("rooms").select("id").limit(1).maybeSingle()
  return data?.id ?? null
}

const SCENARIO_BUILDERS = {
  posts: async (userId, adminUserId) => {
    const { data: post, error } = await supabase
      .from("posts")
      .insert({
        user_id: userId,
        caption: "beta cleanup test post",
        pnl: 0,
        rr: 0,
      })
      .select("id")
      .single()
    if (error) throw new Error(`seed post: ${error.message}`)

    if (adminUserId && adminUserId !== userId) {
      const { error: likeErr } = await supabase.from("likes").insert({
        user_id: adminUserId,
        post_id: post.id,
      })
      if (likeErr) throw new Error(`seed like on owned post: ${likeErr.message}`)
    }
  },
  trades: async (userId, adminUserId) => {
    const { data: trade, error } = await supabase
      .from("trades")
      .insert({
        user_id: userId,
        ticker: "TEST",
        direction: "long",
        pnl: 1,
        rr: 1,
        trade_date: new Date().toISOString().slice(0, 10),
      })
      .select("id")
      .single()
    if (error) throw new Error(`seed trade: ${error.message}`)

    if (adminUserId && adminUserId !== userId) {
      const { error: likeErr } = await supabase.from("trade_likes").insert({
        user_id: adminUserId,
        trade_id: trade.id,
      })
      if (likeErr) throw new Error(`seed like on owned trade: ${likeErr.message}`)
    }
  },
  likes: async (userId) => {
    const postId = await findAnyPostId()
    if (!postId) throw new Error("no post available to like")
    const { error } = await supabase.from("likes").insert({
      user_id: userId,
      post_id: postId,
    })
    if (error) throw new Error(`seed like: ${error.message}`)
  },
  room_messages: async (userId) => {
    const roomId = await findAnyRoomId()
    if (!roomId) throw new Error("no room available for message")
    await supabase.from("room_members").upsert({
      room_id: roomId,
      user_id: userId,
    })
    const { error } = await supabase.from("room_messages").insert({
      room_id: roomId,
      user_id: userId,
      content: "beta cleanup room message",
    })
    if (error) throw new Error(`seed room message: ${error.message}`)
  },
  owned_room: async (userId) => {
    const { data, error } = await supabase
      .from("rooms")
      .insert({
        name: `Beta Cleanup Room ${Date.now()}`,
        owner_user_id: userId,
        is_private: false,
      })
      .select("id")
      .single()
    if (error) throw new Error(`seed owned room: ${error.message}`)
    const { error: msgErr } = await supabase.from("room_messages").insert({
      room_id: data.id,
      user_id: userId,
      content: "owned room message",
    })
    if (msgErr) throw new Error(`seed owned room message: ${msgErr.message}`)
  },
}

async function verifyNoReferences(userId) {
  const { data: profile } = await supabase
    .from("profiles")
    .select("id")
    .eq("id", userId)
    .maybeSingle()
  const { data: authData } = await supabase.auth.admin.getUserById(userId)

  const leftovers = []
  for (const [table, col] of REFERENCE_TABLES) {
    const { count, error } = await supabase
      .from(table)
      .select("*", { count: "exact", head: true })
      .eq(col, userId)
    if (error?.code === "PGRST205") continue
    if ((count ?? 0) > 0) leftovers.push(`${table}.${col}=${count}`)
  }

  return {
    profileRemoved: !profile?.id,
    authRemoved: !authData?.user?.id,
    leftovers,
  }
}

async function main() {
  const adminUserId = await findAdminId()
  if (!adminUserId) {
    console.error("No admin user found")
    process.exit(1)
  }

  const only = process.argv[2]
  const scenarios = Object.keys(SCENARIO_BUILDERS).filter(
    (key) => !only || key === only || key.includes(only)
  )

  const results = []

  for (const scenario of scenarios) {
    console.log(`\n=== scenario: ${scenario} ===`)
    let userId = null
    try {
      const user = await createTestUser(scenario)
      userId = user.userId
      console.log("created:", userId, user.email)

      await SCENARIO_BUILDERS[scenario](userId, adminUserId)

      const result = await deleteUserAdmin(supabase, {
        adminUserId,
        targetUserId: userId,
        stripe: null,
      })
      console.log("deleteUserAdmin:", result)

      const verification = await verifyNoReferences(userId)
      const ok =
        verification.profileRemoved &&
        verification.authRemoved &&
        verification.leftovers.length === 0

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

  const failed = results.filter((r) => !r.ok)
  process.exit(failed.length > 0 ? 1 : 0)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
