/**
 * Validates DM preservation during deleteUserAdmin (messages anonymized, not removed).
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
  const email = `dm-cleanup-${label}-${Date.now()}@tradetraxs-test.invalid`
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
    username: `dm_${label}_${data.user.id.slice(0, 6)}`,
    updated_at: new Date().toISOString(),
  })

  return { userId: data.user.id, conversationId: null }
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

async function createConversation() {
  const { data, error } = await supabase
    .from("conversations")
    .insert({ is_group: false })
    .select("id")
    .single()
  if (error) throw new Error(`create conversation: ${error.message}`)
  return data.id
}

async function countDirectMessages(userId) {
  const { count, error } = await supabase
    .from("direct_messages")
    .select("*", { count: "exact", head: true })
    .or(`sender_id.eq.${userId},recipient_id.eq.${userId}`)
  if (error) throw new Error(`count direct_messages: ${error.message}`)
  return count ?? 0
}

async function countMessagesBySender(userId) {
  const { count, error } = await supabase
    .from("messages")
    .select("*", { count: "exact", head: true })
    .eq("sender_id", userId)
  if (error) throw new Error(`count messages by sender: ${error.message}`)
  return count ?? 0
}

async function countAnonymizedMessages(conversationId) {
  const { count, error } = await supabase
    .from("messages")
    .select("*", { count: "exact", head: true })
    .eq("conversation_id", conversationId)
    .eq("sender_anonymized", true)
  if (error) throw new Error(`count anonymized messages: ${error.message}`)
  return count ?? 0
}

async function countConversationMessages(conversationId) {
  const { count, error } = await supabase
    .from("messages")
    .select("*", { count: "exact", head: true })
    .eq("conversation_id", conversationId)
  if (error) throw new Error(`count conversation messages: ${error.message}`)
  return count ?? 0
}

const SCENARIOS = {
  legacy_direct_messages: async (targetId, otherId) => {
    const conversationId = await createConversation()
    const { error: sentErr } = await supabase.from("direct_messages").insert({
      conversation_id: conversationId,
      sender_id: targetId,
      content: "legacy dm as sender",
    })
    if (sentErr) throw new Error(`seed direct_messages sender: ${sentErr.message}`)

    const { error: recvErr } = await supabase.from("direct_messages").insert({
      conversation_id: conversationId,
      sender_id: otherId,
      recipient_id: targetId,
      content: "legacy dm as recipient",
    })
    if (recvErr) throw new Error(`seed direct_messages recipient: ${recvErr.message}`)
    return conversationId
  },
  modern_messages: async (targetId, otherId) => {
    const conversationId = await createConversation()
    await supabase.from("conversation_participants").insert([
      { conversation_id: conversationId, user_id: targetId },
      { conversation_id: conversationId, user_id: otherId },
    ])
    const { error } = await supabase.from("messages").insert({
      conversation_id: conversationId,
      sender_id: targetId,
      user_id: targetId,
      content: "modern dm message",
    })
    if (error) throw new Error(`seed messages: ${error.message}`)
    return conversationId
  },
  both: async (targetId, otherId) => {
    await SCENARIOS.legacy_direct_messages(targetId, otherId)
    return SCENARIOS.modern_messages(targetId, otherId)
  },
}

async function verifyDeleted(userId, conversationId, scenario) {
  const { data: profile } = await supabase
    .from("profiles")
    .select("id")
    .eq("id", userId)
    .maybeSingle()
  const { data: authData } = await supabase.auth.admin.getUserById(userId)
  const directMessagesLeft = await countDirectMessages(userId)
  const messagesBySenderLeft = await countMessagesBySender(userId)
  const anonymizedCount = conversationId
    ? await countAnonymizedMessages(conversationId)
    : 0
  const conversationMessagesLeft = conversationId
    ? await countConversationMessages(conversationId)
    : 0
  const { data: audit } = await supabase
    .from("admin_audit_log")
    .select("id, action, target_id")
    .eq("target_id", userId)
    .eq("action", "delete_user")
    .order("created_at", { ascending: false })
    .limit(1)

  const expectsModernPreservation =
    scenario === "modern_messages" || scenario === "both"

  return {
    profileRemoved: !profile?.id,
    authRemoved: !authData?.user?.id,
    directMessagesLeft,
    messagesBySenderLeft,
    anonymizedCount,
    conversationMessagesLeft,
    auditCreated: Boolean(audit?.length),
    expectsModernPreservation,
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
    let conversationId = null
    try {
      const created = await createTestUser(scenario)
      userId = created.userId
      const otherId = await findOtherProfileId(userId)
      if (!otherId) throw new Error("no other profile for message seed")

      conversationId = await SCENARIOS[scenario](userId, otherId)
      const dmBefore = await countDirectMessages(userId)
      const msgBefore = await countMessagesBySender(userId)
      console.log("seeded direct_messages:", dmBefore, "messages by sender:", msgBefore)

      await deleteUserAdmin(supabase, {
        adminUserId,
        targetUserId: userId,
        stripe: null,
      })

      const verification = await verifyDeleted(userId, conversationId, scenario)
      const ok =
        verification.profileRemoved &&
        verification.authRemoved &&
        verification.directMessagesLeft === 0 &&
        verification.messagesBySenderLeft === 0 &&
        verification.auditCreated &&
        (!verification.expectsModernPreservation ||
          (verification.anonymizedCount >= 1 &&
            verification.conversationMessagesLeft >= 1))

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
