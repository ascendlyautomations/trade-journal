// Reproduce the shared-media RPC 400 as an authenticated participant.
// Creates an isolated throwaway user + conversation, calls the RPC, prints the
// exact PostgREST error, then deletes everything it created.
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"

const env = {}
for (const line of readFileSync(".env.local", "utf8").split(/\r?\n/)) {
  const eq = line.indexOf("=")
  if (eq > 0) env[line.slice(0, eq).trim()] = line.slice(eq + 1).trim()
}

const url = env.NEXT_PUBLIC_SUPABASE_URL
const admin = createClient(url, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
})
const userClient = createClient(url, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
})

const email = `shared-media-probe-${Date.now()}@example.com`
const password = `Probe-${Date.now()}-x9!Q`
let userId = null
let conversationId = null
const messageIds = []

async function cleanup() {
  try {
    if (messageIds.length) {
      await admin.from("messages").delete().in("id", messageIds)
    }
    if (conversationId) {
      await admin
        .from("conversation_participants")
        .delete()
        .eq("conversation_id", conversationId)
      await admin.from("conversations").delete().eq("id", conversationId)
    }
    if (userId) {
      await admin.from("profiles").delete().eq("id", userId)
      await admin.auth.admin.deleteUser(userId)
    }
    console.log("\n[cleanup] done")
  } catch (e) {
    console.error("[cleanup] FAILED — manual cleanup may be needed:", e)
  }
}

try {
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  })
  if (createErr) throw createErr
  userId = created.user.id
  console.log("[setup] test user:", userId)

  const { data: convo, error: convoErr } = await admin
    .from("conversations")
    .insert({})
    .select("id")
    .single()
  if (convoErr) throw convoErr
  conversationId = convo.id

  const { error: partErr } = await admin
    .from("conversation_participants")
    .insert({ conversation_id: conversationId, user_id: userId })
  if (partErr) throw partErr

  const { data: msg, error: msgErr } = await admin
    .from("messages")
    .insert({
      conversation_id: conversationId,
      sender_id: userId,
      content: "probe",
      type: "text",
      image_url: "https://example.com/probe.png",
    })
    .select("id")
    .single()
  if (msgErr) throw msgErr
  messageIds.push(msg.id)
  console.log("[setup] conversation:", conversationId, "message:", msg.id)

  const { error: signInErr } = await userClient.auth.signInWithPassword({
    email,
    password,
  })
  if (signInErr) throw signInErr

  const { data, error } = await userClient.rpc("get_conversation_shared_media", {
    p_conversation_id: conversationId,
    p_before_created_at: null,
    p_before_id: null,
    p_limit: 12,
  })

  console.log("\n=== RPC as authenticated participant ===")
  if (error) {
    console.log("ERROR:", JSON.stringify(error, null, 2))
  } else {
    console.log("OK, rows:", JSON.stringify(data, null, 2))
  }
} finally {
  await cleanup()
}
