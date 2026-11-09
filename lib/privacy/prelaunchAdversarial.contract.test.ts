/**
 * Pre-launch adversarial authorization contracts.
 *
 * These read migration and route source only. They do not connect to a
 * database, call production, or print secrets. They fail while the
 * corresponding access-control gaps are still present.
 */
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const root = process.cwd()
const migrationsDir = path.join(root, "supabase/migrations")

function migrationFiles(): string[] {
  return fs
    .readdirSync(migrationsDir)
    .filter((name) => name.endsWith(".sql"))
    .sort()
}

function readMigration(name: string): string {
  return fs.readFileSync(path.join(migrationsDir, name), "utf8")
}

function latestFunctionBody(functionName: string): { file: string; body: string } {
  const needle = `function public.${functionName}`
  let found: { file: string; body: string } | null = null
  for (const file of migrationFiles()) {
    const sql = readMigration(file)
    let searchFrom = 0
    while (searchFrom < sql.length) {
      const idx = sql.indexOf(needle, searchFrom)
      if (idx === -1) break
      const createIdx = sql.lastIndexOf("create or replace", idx)
      if (createIdx !== -1 && idx - createIdx < 80) {
        const slice = sql.slice(createIdx)
        const end = slice.search(/\n\$\$;/)
        if (end !== -1) found = { file, body: slice.slice(0, end) }
      }
      searchFrom = idx + needle.length
    }
  }
  assert.ok(found, `missing function public.${functionName}`)
  return found!
}

function latestPolicyBody(policyName: string): { file: string; body: string } {
  const needle = `create policy "${policyName}"`
  let found: { file: string; body: string } | null = null
  for (const file of migrationFiles()) {
    const sql = readMigration(file)
    const idx = sql.lastIndexOf(needle)
    if (idx === -1) continue
    const slice = sql.slice(idx)
    const end = slice.indexOf(");")
    assert.ok(end !== -1, `${policyName} policy in ${file} did not close`)
    found = { file, body: slice.slice(0, end) }
  }
  assert.ok(found, `missing policy ${policyName}`)
  return found!
}

describe("prelaunch adversarial authorization", () => {
  it("DM message-row RPC only returns rows the caller participates in", () => {
    const fn = latestFunctionBody("rpc_v1_conversation_thread_message_row")
    assert.match(
      fn.body,
      /is_conversation_participant\s*\(/,
      `${fn.file}: rpc_v1_conversation_thread_message_row is security definer and granted to authenticated, so it must reject non-participants before returning content`
    )
    assert.match(fn.body, /auth\.uid\(\)/)
  })

  it("room message-row RPC only returns rows the caller can read", () => {
    const fn = latestFunctionBody("rpc_v1_room_bootstrap_message_row")
    assert.match(
      fn.body,
      /is_active_room_member\s*\(|can_read_trade_room_messages\s*\(|profile_is_visible_to_viewer\s*\(/,
      `${fn.file}: rpc_v1_room_bootstrap_message_row must check room read access, not only the author visibility predicate`
    )
  })

  it("room bootstrap message row includes voice metadata", () => {
    const fn = latestFunctionBody("rpc_v1_room_bootstrap_message_row")
    assert.match(fn.body, /'audio_url',\s*m\.audio_url/)
    assert.match(fn.body, /'audio_duration_ms',\s*m\.audio_duration_ms/)
  })

  it("private community rooms are not listed to every authenticated user", () => {
    const policy = latestPolicyBody("rooms_select_invite")
    assert.doesNotMatch(
      policy.body,
      /coalesce\(is_private,\s*false\)\s*=\s*true/,
      `${policy.file}: rooms_select_invite currently matches every private community room with a slug`
    )
    assert.match(
      policy.body,
      /is_active_room_member\s*\(|room_members/,
      "invite SELECT must be limited to members or a single invite capability"
    )
  })

  it("room message inserts refuse platform-banned authors", () => {
    const policy = latestPolicyBody("room_messages_insert_member")
    assert.match(
      policy.body,
      /is_banned/,
      `${policy.file}: room_messages_insert_member must reject profiles.is_banned, not only new joins`
    )
  })

  it("room message updates do not fall through for non-members", () => {
    const fn = latestFunctionBody("room_messages_before_update_guard")
    assert.match(
      fn.body,
      /not an active room member|room_message_update_denied/,
      `${fn.file}: non-members and service-role callers with a null auth.uid() currently hit a bare return new`
    )
  })

  it("voice notes are not stored in a public bucket", () => {
    let isPublic: boolean | null = null
    for (const file of migrationFiles()) {
      const sql = readMigration(file)
      if (/'message-audio',\s*'message-audio',\s*true/.test(sql)) isPublic = true
      if (/'message-audio',\s*'message-audio',\s*false/.test(sql)) isPublic = false
      if (/update\s+storage\.buckets\s+set\s+public\s*=\s*false[\s\S]{0,120}message-audio/i.test(sql)) {
        isPublic = false
      }
    }
    assert.equal(
      isPublic,
      false,
      "message-audio is created public; private voice notes need public = false and signed or authenticated reads"
    )
  })

  it("DM image uploads do not publish permanent public screenshot URLs", () => {
    const page = fs.readFileSync(
      path.join(root, "app/(app)/messages/[id]/page.tsx"),
      "utf8"
    )
    assert.doesNotMatch(
      page,
      /\/storage\/v1\/object\/public\/screenshots\//,
      "DM images are written to the public screenshots bucket with a predictable {userId}/opt/{timestamp} path"
    )
  })

  it("mark-read refuses conversations and rooms the caller is not in", () => {
    const src = fs.readFileSync(path.join(root, "lib/server/guardedMarkRead.ts"), "utf8")
    const conversationFn = src.slice(
      src.indexOf("export async function markConversationReadForUser"),
      src.indexOf("export async function markRoomReadForUser")
    )
    const roomFn = src.slice(src.indexOf("export async function markRoomReadForUser"))
    assert.match(
      conversationFn,
      /conversation_participants/,
      "markConversationReadForUser must load conversation_participants and return before any service-role write"
    )
    const roomSeen = roomFn.indexOf("seen_by")
    const roomGate = roomFn.search(/if\s*\(\s*!member\b/)
    assert.ok(
      roomGate !== -1 && roomSeen !== -1 && roomGate < roomSeen,
      "markRoomReadForUser must return when the caller has no active room_members row before updating seen_by"
    )
  })

  it("DM push notify is idempotent for a replayed message id", () => {
    const src = fs.readFileSync(
      path.join(root, "lib/server/notifications/handlers/dmNotify.ts"),
      "utf8"
    )
    const emitAt = src.indexOf("emitDmPushes")
    assert.ok(emitAt !== -1)
    assert.match(
      src.slice(0, emitAt),
      /idempoten|dedup|already_scheduled|delivery ledger|rate_limit_hit/i,
      "notify-dm verifies the sender, then schedules another push on every replay of the same messageId"
    )
  })

  it("profile bootstrap does not grant is_pro before payment", () => {
    const src = fs.readFileSync(path.join(root, "lib/ensureProfileForUser.ts"), "utf8")
    assert.doesNotMatch(
      src,
      /is_pro:\s*true/,
      "ensureProfileForUser inserts is_pro true. Checkout calls it with the service role when the profile row is missing, and isProActive treats that flag as TraxPro."
    )
  })
})
