/**
 * Server-side replay of the inbox Supabase pipeline (steps 1–4).
 * Run: node scripts/trace-messages-inbox-pipeline.mjs
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "fs"

const env = Object.fromEntries(
  readFileSync(".env.local", "utf8")
    .split(/\r?\n/)
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => {
      const i = l.indexOf("=")
      return [l.slice(0, i), l.slice(i + 1)]
    })
)

const admin = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY
)
const anon = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.NEXT_PUBLIC_SUPABASE_ANON_KEY
)

function log(step, payload) {
  console.log(`[pipeline-trace] ${step}`, JSON.stringify(payload, null, 2))
}

const { data: usersData } = await admin.auth.admin.listUsers({ perPage: 100 })
const usersWithParticipants = []

for (const user of usersData?.users ?? []) {
  const { count } = await admin
    .from("conversation_participants")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.id)
  if ((count ?? 0) > 0) {
    usersWithParticipants.push({ id: user.id, email: user.email, count })
  }
}

log("users-with-conversations", usersWithParticipants)

if (usersWithParticipants.length === 0) {
  console.log("No users with conversation_participants rows found.")
  process.exit(0)
}

const target = usersWithParticipants[0]
const userId = target.id

log("step:0-target-user", target)

// Unauthenticated (simulates missing session)
{
  const { data: rows, error } = await anon
    .from("conversation_participants")
    .select(
      `conversation_id, conversations ( id, last_message, last_message_at )`
    )
    .eq("user_id", userId)
  log("step:2-unauthenticated", {
    error: error?.message ?? null,
    rowCount: rows?.length ?? 0,
    firstRow: rows?.[0] ?? null,
  })
}

// Authenticated via magic link
const { data: link } = await admin.auth.admin.generateLink({
  type: "magiclink",
  email: target.email,
})
const token = link?.properties?.hashed_token
if (!token) {
  console.error("Could not generate magic link token")
  process.exit(1)
}

const { data: sessionData, error: otpErr } = await anon.auth.verifyOtp({
  type: "magiclink",
  token_hash: token,
})

const session = sessionData.session
log("step:1-auth", {
  sessionExists: Boolean(session),
  sessionUserId: session?.user?.id ?? null,
  authUserId: userId,
  sessionUserIdMatches: session?.user?.id === userId,
  otpError: otpErr?.message ?? null,
})

const { data: rows, error } = await anon
  .from("conversation_participants")
  .select(
    `
    conversation_id,
    conversations (
      id,
      is_group,
      is_pinned,
      name,
      avatar_url,
      last_message,
      last_message_at
    )
  `
  )
  .eq("user_id", userId)

log("step:2-participants-authenticated", {
  error: error?.message ?? null,
  rowCount: rows?.length ?? 0,
  firstRow: rows?.[0] ?? null,
})

const convoIds = (rows ?? []).map((r) => r.conversation_id)
const firstConvoMeta = (() => {
  const first = rows?.[0]
  const meta = Array.isArray(first?.conversations)
    ? first?.conversations?.[0]
    : first?.conversations
  return meta ?? null
})()

log("step:3-conversations-embed", {
  rowCount: rows?.length ?? 0,
  conversationIds: convoIds,
  firstConversation: firstConvoMeta,
  nestedConversationsNull: (rows ?? []).filter((r) => !r.conversations).length,
})

const { data: participantRows, error: participantError } = await anon
  .from("conversation_participants")
  .select(
    `
    conversation_id,
    user_id,
    profiles (id, username, avatar_url, name)
  `
  )
  .in("conversation_id", convoIds)

log("step:4-participant-profiles", {
  participantError: participantError?.message ?? null,
  participantRowCount: participantRows?.length ?? 0,
})

log("step:4-last-message", {
  conversationId: firstConvoMeta?.id ?? null,
  lastMessageExists: Boolean(firstConvoMeta?.last_message?.trim()),
  lastMessage: firstConvoMeta?.last_message ?? null,
})

log("step:5-mapped-length", {
  conversationsLength: convoIds.length,
})
