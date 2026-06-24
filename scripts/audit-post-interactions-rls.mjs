/**
 * Probe comments/likes SELECT+INSERT as authenticated user (RLS applies).
 * Usage: node scripts/audit-post-interactions-rls.mjs <email> <password>
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

const [email, password] = process.argv.slice(2)
if (!email || !password) {
  console.error("Usage: node scripts/audit-post-interactions-rls.mjs <email> <password>")
  process.exit(1)
}

const env = loadEnv()
const sb = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.NEXT_PUBLIC_SUPABASE_ANON_KEY
)

const { data: auth, error: authErr } = await sb.auth.signInWithPassword({
  email,
  password,
})
if (authErr || !auth.user) {
  console.error("auth failed:", authErr?.message)
  process.exit(1)
}
console.log("authenticated as:", auth.user.id)

const { data: tradePost } = await sb.from("posts").select("id").limit(1).maybeSingle()
const { data: profilePost } = await sb
  .from("profile_posts")
  .select("id")
  .limit(1)
  .maybeSingle()

if (tradePost?.id) {
  const { data: selectRows, error: selectErr } = await sb
    .from("comments")
    .select("id")
    .eq("post_id", tradePost.id)
    .limit(1)
  console.log("\ncomments SELECT (posts id):", {
    error: selectErr?.code,
    message: selectErr?.message,
    rowCount: selectRows?.length ?? 0,
  })

  const payload = {
    post_id: tradePost.id,
    user_id: auth.user.id,
    content: "rls audit comment — delete me",
  }
  const { data: inserted, error: insertErr } = await sb
    .from("comments")
    .insert(payload)
    .select("id")
    .single()
  console.log("comments INSERT (posts id):", {
    payload,
    error: insertErr?.code,
    message: insertErr?.message,
    insertedId: inserted?.id ?? null,
  })
  if (inserted?.id) {
    await sb.from("comments").delete().eq("id", inserted.id)
  }

  const likePayload = { post_id: tradePost.id, user_id: auth.user.id }
  const { error: likeErr } = await sb.from("likes").insert(likePayload)
  console.log("likes INSERT (posts id):", {
    payload: likePayload,
    error: likeErr?.code,
    message: likeErr?.message,
  })
  if (!likeErr) {
    await sb
      .from("likes")
      .delete()
      .eq("post_id", tradePost.id)
      .eq("user_id", auth.user.id)
  }
}

if (profilePost?.id) {
  const likePayload = { post_id: profilePost.id, user_id: auth.user.id }
  const { error: likeErr } = await sb.from("likes").insert(likePayload)
  console.log("\nlikes INSERT (profile_posts id as post_id):", {
    payload: likePayload,
    error: likeErr?.code,
    message: likeErr?.message,
    details: likeErr?.details,
  })
}

await sb.auth.signOut()
