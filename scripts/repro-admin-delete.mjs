/**
 * Executes deleteUserAdmin step-by-step on a target user to capture first failure.
 * WARNING: mutates data — only use on test accounts.
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

const targetUserId = process.argv[2]
const adminUserId = process.argv[3]

if (!targetUserId || !adminUserId) {
  console.error("Usage: node scripts/repro-admin-delete.mjs <targetUserId> <adminUserId>")
  process.exit(1)
}

async function step(name, fn) {
  process.stdout.write(`STEP ${name}... `)
  try {
    await fn()
    console.log("OK")
    return true
  } catch (err) {
    console.log("FAIL")
    console.error("  error:", err instanceof Error ? err.message : err)
    if (err instanceof Error && err.stack) console.error(err.stack)
    return false
  }
}

async function deleteOr(table, orFilter) {
  const { error } = await supabase.from(table).delete().or(orFilter)
  if (error) throw new Error(`${table}: ${error.message} (${error.code}) ${error.details ?? ""}`)
}

async function deleteWhere(table, column, value) {
  const { error } = await supabase.from(table).delete().eq(column, value)
  if (error) throw new Error(`${table}.${column}: ${error.message} (${error.code}) ${error.details ?? ""}`)
}

async function main() {
  console.log("target:", targetUserId, "admin:", adminUserId)

  const { data: ownedRooms } = await supabase
    .from("rooms")
    .select("id")
    .eq("owner_user_id", targetUserId)
  const ownedRoomIds = (ownedRooms ?? []).map((r) => String(r.id))

  const steps = [
    ["stripe skip", async () => {}],
    [
      "owned room cleanup",
      async () => {
        if (!ownedRoomIds.length) return
        for (const [table, col] of [
          ["room_messages", "room_id"],
          ["room_members", "room_id"],
          ["room_bans", "room_id"],
          ["room_sections", "room_id"],
        ]) {
          const { error } = await supabase.from(table).delete().in(col, ownedRoomIds)
          if (error) throw new Error(`${table}: ${error.message}`)
        }
        await deleteWhere("rooms", "owner_user_id", targetUserId)
      },
    ],
    ["room_members", () => deleteWhere("room_members", "user_id", targetUserId)],
    ["room_bans user", () => deleteWhere("room_bans", "user_id", targetUserId)],
    [
      "followers",
      () =>
        deleteOr(
          "followers",
          `follower_id.eq.${targetUserId},following_id.eq.${targetUserId}`
        ),
    ],
    [
      "follow_requests",
      () =>
        deleteOr(
          "follow_requests",
          `requester_id.eq.${targetUserId},target_id.eq.${targetUserId}`
        ),
    ],
    [
      "notifications",
      () =>
        deleteOr(
          "notifications",
          `user_id.eq.${targetUserId},sender_id.eq.${targetUserId}`
        ),
    ],
    ["message_likes", () => deleteWhere("message_likes", "user_id", targetUserId)],
    ["message_comments", () => deleteWhere("message_comments", "user_id", targetUserId)],
    ["message_deletions", () => deleteWhere("message_deletions", "user_id", targetUserId)],
    [
      "messages",
      () =>
        deleteOr(
          "messages",
          `sender_id.eq.${targetUserId},user_id.eq.${targetUserId}`
        ),
    ],
    [
      "conversation_participants",
      () => deleteWhere("conversation_participants", "user_id", targetUserId),
    ],
    ["trade_likes", () => deleteWhere("trade_likes", "user_id", targetUserId)],
    ["trade_comments", () => deleteWhere("trade_comments", "user_id", targetUserId)],
    ["comments by user", () => deleteWhere("comments", "user_id", targetUserId)],
    ["posts", () => deleteWhere("posts", "user_id", targetUserId)],
    ["trades", () => deleteWhere("trades", "user_id", targetUserId)],
    ["profile_posts", () => deleteWhere("profile_posts", "user_id", targetUserId)],
    ["accounts", () => deleteWhere("accounts", "user_id", targetUserId)],
    ["profile", () => deleteWhere("profiles", "id", targetUserId)],
    ["auth user", async () => {
      const { error } = await supabase.auth.admin.deleteUser(targetUserId)
      if (error) throw new Error(error.message)
    }],
  ]

  for (const [name, fn] of steps) {
    const ok = await step(name, fn)
    if (!ok) break
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
