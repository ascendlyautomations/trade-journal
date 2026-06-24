/**
 * Read-only audit: probe likes/comments inserts for posts vs profile_posts IDs.
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
const sb = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY
)

const { data: realUser } = await sb
  .from("profiles")
  .select("id")
  .limit(1)
  .maybeSingle()

const probeUserId = realUser?.id ?? fakeUser
console.log("probe user_id:", probeUserId)

const { data: profilePost } = await sb
  .from("profile_posts")
  .select("id")
  .limit(1)
  .maybeSingle()

const { data: tradePost } = await sb
  .from("posts")
  .select("id")
  .limit(1)
  .maybeSingle()

console.log("sample profile_posts.id:", profilePost?.id ?? null)
console.log("sample posts.id:", tradePost?.id ?? null)

if (profilePost?.id) {
  const payload = { post_id: profilePost.id, user_id: probeUserId }
  const { error } = await sb.from("likes").insert(payload)
  console.log("\nlikes INSERT (profile_posts id as post_id):")
  console.log("  payload:", payload)
  console.log("  error:", error?.code, error?.message, error?.details)
}

if (tradePost?.id) {
  const payload = { post_id: tradePost.id, user_id: probeUserId }
  const { error } = await sb.from("likes").insert(payload)
  console.log("\nlikes INSERT (posts id as post_id):")
  console.log("  payload:", payload)
  console.log("  error:", error?.code, error?.message, error?.details)
}

if (profilePost?.id) {
  const payload = {
    post_id: profilePost.id,
    user_id: probeUserId,
    content: "audit test comment",
  }
  const { error } = await sb.from("comments").insert(payload)
  console.log("\ncomments INSERT (profile_posts id as post_id):")
  console.log("  payload:", payload)
  console.log("  error:", error?.code, error?.message, error?.details)
}

if (tradePost?.id) {
  const payload = {
    post_id: tradePost.id,
    user_id: probeUserId,
    content: "audit test comment",
  }
  const { error } = await sb.from("comments").insert(payload)
  console.log("\ncomments INSERT (posts id as post_id):")
  console.log("  payload:", payload)
  console.log("  error:", error?.code, error?.message, error?.details)
}
