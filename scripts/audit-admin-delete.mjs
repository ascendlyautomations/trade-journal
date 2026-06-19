/**
 * Admin delete failure audit — counts only, no mutations.
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

async function count(table, column, value) {
  const { count, error } = await supabase
    .from(table)
    .select("*", { count: "exact", head: true })
    .eq(column, value)
  return { count: count ?? 0, error: error?.message ?? null, code: error?.code ?? null }
}

async function countOr(table, orFilter) {
  const { count, error } = await supabase
    .from(table)
    .select("*", { count: "exact", head: true })
    .or(orFilter)
  return { count: count ?? 0, error: error?.message ?? null, code: error?.code ?? null }
}

async function main() {
  const usernames = process.argv.slice(2)
  if (usernames.length === 0) {
    usernames.push("fasdfasdfasdfasdfadsffdsafads", "424test")
  }

  const { data: admins } = await supabase.from("admin_users").select("user_id")
  console.log("admin_users count:", admins?.length ?? 0)

  for (const username of usernames) {
    console.log("\n=== USER:", username, "===")
    const { data: profile, error: profErr } = await supabase
      .from("profiles")
      .select("id, username, stripe_customer_id, created_at, subscription_status")
      .eq("username", username)
      .maybeSingle()

    if (profErr || !profile?.id) {
      console.log("Profile lookup:", profErr?.message ?? "not found")
      continue
    }

    const userId = profile.id
    console.log("userId:", userId)
    console.log("stripe_customer_id:", profile.stripe_customer_id ?? "(none)")

    const { data: authData, error: authErr } =
      await supabase.auth.admin.getUserById(userId)
    console.log("auth:", authData?.user?.email ?? "(none)", authErr?.message ?? "")

    const isAdmin = admins?.some((a) => a.user_id === userId)
    console.log("is_admin:", isAdmin)

    const probes = [
      ["trades", "user_id", userId],
      ["posts", "user_id", userId],
      ["comments", "user_id", userId],
      ["trade_comments", "user_id", userId],
      ["trade_likes", "user_id", userId],
      ["likes", "user_id", userId],
      ["messages", "sender_id", userId],
      ["messages", "user_id", userId],
      ["message_likes", "user_id", userId],
      ["message_comments", "user_id", userId],
      ["message_deletions", "user_id", userId],
      ["conversation_participants", "user_id", userId],
      ["room_messages", "user_id", userId],
      ["rooms", "owner_user_id", userId],
      ["room_members", "user_id", userId],
      ["room_bans", "user_id", userId],
      ["room_bans", "banned_by", userId],
      ["notifications", "user_id", userId],
      ["affiliates", "user_id", userId],
      ["accounts", "user_id", userId],
      ["saved_posts", "user_id", userId],
      ["saved_trades", "user_id", userId],
    ]

    for (const [table, col, val] of probes) {
      const r = await count(table, col, val)
      const flag = r.error ? ` TABLE_ERROR: ${r.error}` : r.count > 0 ? " *" : ""
      console.log(`  ${table}.${col}: ${r.count}${flag}`)
    }

    for (const [label, table, orFilter] of [
      ["followers", "followers", `follower_id.eq.${userId},following_id.eq.${userId}`],
      ["follows (legacy)", "follows", `follower_id.eq.${userId},following_id.eq.${userId}`],
      [
        "direct_messages (legacy)",
        "direct_messages",
        `sender_id.eq.${userId},recipient_id.eq.${userId}`,
      ],
      ["follow_requests", "follow_requests", `requester_id.eq.${userId},target_id.eq.${userId}`],
    ]) {
      const r = await countOr(table, orFilter)
      const flag = r.error ? ` TABLE_ERROR: ${r.error}` : r.count > 0 ? " *" : ""
      console.log(`  ${label} (or): ${r.count}${flag}`)
    }

    const { data: postIds } = await supabase
      .from("posts")
      .select("id")
      .eq("user_id", userId)
    if (postIds?.length) {
      const ids = postIds.map((p) => p.id)
      const { count: likeCount, error: likeErr } = await supabase
        .from("likes")
        .select("*", { count: "exact", head: true })
        .in("post_id", ids)
      const { count: commentCount, error: commentErr } = await supabase
        .from("comments")
        .select("*", { count: "exact", head: true })
        .in("post_id", ids)
      console.log(
        `  likes on user posts: ${likeCount ?? 0}`,
        likeErr?.message ?? ""
      )
      console.log(
        `  comments on user posts (any author): ${commentCount ?? 0}`,
        commentErr?.message ?? ""
      )
    }
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
