#!/usr/bin/env node
/**
 * Remove ONLY load-test-tagged rows in fixture-scoped conversations/rooms.
 *
 * Profiles (auto-detected from fixture env, or pass --realistic1000 / --realistic600):
 *   realistic300_full — [loadtest:realistic300_full] + LOADTEST_REALISTIC300_FULL_FIXTURE_*
 *   realistic600_full — [loadtest:realistic600_full] + LOADTEST_REALISTIC600_FULL_FIXTURE_*
 *   realistic1000_full — [loadtest:realistic1000_full] + LOADTEST_REALISTIC1000_FULL_FIXTURE_* (or 600 fixture env)
 *
 * Every delete/patch query requires BOTH fixture scope AND content tag filter.
 *
 * Dry-run: no Auth HTTP — previews scoped operations per perf account.
 * Live: throttled password grants with 429 backoff (Retry-After + exponential jitter).
 */

import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const __dirname = dirname(fileURLToPath(import.meta.url))
const dryRun = process.argv.includes("--dry-run")
const force1000 = process.argv.includes("--realistic1000")
const force600 = process.argv.includes("--realistic600")

function readTagFromModule(relativePath, exportName) {
  const tagModulePath = join(__dirname, relativePath)
  const tagSource = readFileSync(tagModulePath, "utf8")
  const re = new RegExp(`${exportName} = "([^"]+)"`)
  const tagMatch = tagSource.match(re)
  if (!tagMatch) {
    throw new Error(`Could not read ${exportName} from ${tagModulePath}`)
  }
  return tagMatch[1]
}

function resolveCleanupProfile() {
  const has1000Fixture =
    force1000 ||
    process.env.LOADTEST_CLEANUP_PROFILE === "realistic1000" ||
    Boolean(process.env.LOADTEST_REALISTIC1000_FULL_FIXTURE_JSON?.trim()) ||
    Boolean(process.env.LOADTEST_REALISTIC1000_FULL_FIXTURE_FILE?.trim()) ||
    process.env.LOADTEST_FULL_MESSAGE_TAG?.trim() === "[loadtest:realistic1000_full]"
  if (has1000Fixture) {
    return {
      name: "realistic1000_full",
      tag: readTagFromModule("../lib/realistic1000-full-tag.js", "REALISTIC1000_FULL_MESSAGE_TAG"),
      fixtureJsonKey: "LOADTEST_REALISTIC1000_FULL_FIXTURE_JSON",
      fixtureFileKey: "LOADTEST_REALISTIC1000_FULL_FIXTURE_FILE",
      usersJsonKey: "LOADTEST_REALISTIC600_USERS_JSON",
    }
  }
  const has600Fixture =
    force600 ||
    process.env.LOADTEST_CLEANUP_PROFILE === "realistic600" ||
    Boolean(process.env.LOADTEST_REALISTIC600_FULL_FIXTURE_JSON?.trim()) ||
    Boolean(process.env.LOADTEST_REALISTIC600_FULL_FIXTURE_FILE?.trim())
  if (has600Fixture) {
    return {
      name: "realistic600_full",
      tag: readTagFromModule("../lib/realistic600-full-tag.js", "REALISTIC600_FULL_MESSAGE_TAG"),
      fixtureJsonKey: "LOADTEST_REALISTIC600_FULL_FIXTURE_JSON",
      fixtureFileKey: "LOADTEST_REALISTIC600_FULL_FIXTURE_FILE",
      usersJsonKey: "LOADTEST_REALISTIC600_USERS_JSON",
    }
  }
  return {
    name: "realistic300_full",
    tag: readTagFromModule("../lib/realistic300-full-tag.js", "REALISTIC300_FULL_MESSAGE_TAG"),
    fixtureJsonKey: "LOADTEST_REALISTIC300_FULL_FIXTURE_JSON",
    fixtureFileKey: "LOADTEST_REALISTIC300_FULL_FIXTURE_FILE",
    usersJsonKey: "LOADTEST_USERS_JSON",
  }
}

const PROFILE = resolveCleanupProfile()
const TAG = PROFILE.tag
const likeTag = encodeURIComponent(`*${TAG}*`)

const AUTH_MAX_RETRIES = Number(process.env.LOADTEST_CLEANUP_AUTH_MAX_RETRIES || 8)
const AUTH_MIN_SPACING_MS = Number(process.env.LOADTEST_CLEANUP_AUTH_SPACING_MS || 1200)
const AUTH_MAX_CONCURRENT = Math.min(
  3,
  Math.max(1, Number(process.env.LOADTEST_CLEANUP_AUTH_CONCURRENCY || 1))
)
const USER_CLEANUP_CONCURRENCY = Math.min(
  4,
  Math.max(1, Number(process.env.LOADTEST_CLEANUP_USER_CONCURRENCY || 1))
)

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function env(name) {
  const v = process.env[name]
  if (!v || !String(v).trim()) {
    throw new Error(`Missing ${name}`)
  }
  return String(v).trim()
}

function loadUsers() {
  return JSON.parse(env(PROFILE.usersJsonKey))
}

function loadFixture() {
  let raw = process.env[PROFILE.fixtureJsonKey]
  if (!raw || !String(raw).trim()) {
    let file = process.env[PROFILE.fixtureFileKey]
    if ((!file || !String(file).trim()) && PROFILE.name === "realistic1000_full") {
      raw = process.env.LOADTEST_REALISTIC600_FULL_FIXTURE_JSON
      file = process.env.LOADTEST_REALISTIC600_FULL_FIXTURE_FILE
    }
    if (!raw || !String(raw).trim()) {
      if (!file || !String(file).trim()) {
        throw new Error(
          `Missing ${PROFILE.fixtureJsonKey} or ${PROFILE.fixtureFileKey} (${PROFILE.name})`
        )
      }
      raw = readFileSync(file, "utf8")
    }
  }
  const fixture = JSON.parse(String(raw).trim())
  if (fixture.schemaVersion !== 1) {
    throw new Error("Fixture schemaVersion must be 1")
  }
  return fixture
}

function assertFixtureIds(fixture) {
  const conversationIds = []
  for (const c of fixture.directConversations || []) {
    const id = String(c.id || "").trim()
    if (!UUID_RE.test(id)) {
      throw new Error(`Invalid fixture directConversations.id: ${id}`)
    }
    conversationIds.push(id)
  }
  const roomIds = []
  for (const r of fixture.tradeRooms || []) {
    const id = String(r.id || "").trim()
    if (!UUID_RE.test(id)) {
      throw new Error(`Invalid fixture tradeRooms.id: ${id}`)
    }
    roomIds.push(id)
  }
  if (conversationIds.length === 0 && roomIds.length === 0) {
    throw new Error("Fixture has no conversation or room ids — refusing cleanup")
  }
  return { conversationIds, roomIds }
}

function assertScopedQuery(table, query) {
  if (!query.includes("content=like.")) {
    throw new Error(`Refusing ${table} mutation without content tag filter`)
  }
  if (!query.includes(likeTag) && !query.includes(encodeURIComponent(TAG))) {
    throw new Error(`Refusing ${table} mutation without load-test tag in filter`)
  }
  if (table === "messages" && !query.includes("conversation_id=eq.")) {
    throw new Error("Refusing messages mutation outside fixture conversation_id scope")
  }
  if (table === "room_messages" && !query.includes("room_id=eq.")) {
    throw new Error("Refusing room_messages mutation outside fixture room_id scope")
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function parseRetryAfterMs(res) {
  const raw = res.headers.get("Retry-After")
  if (!raw) {
    return null
  }
  const asNum = Number(raw)
  if (Number.isFinite(asNum) && asNum >= 0) {
    return asNum * 1000
  }
  const asDate = Date.parse(raw)
  if (!Number.isNaN(asDate)) {
    return Math.max(0, asDate - Date.now())
  }
  return null
}

function authBackoffMs(attempt, retryAfterMs) {
  if (retryAfterMs != null) {
    return retryAfterMs + Math.floor(Math.random() * 250)
  }
  const base = Math.min(60_000, 800 * 2 ** attempt)
  return base + Math.floor(Math.random() * base * 0.25)
}

/** Bounded in-flight password grants + minimum spacing between auth starts. */
let authInFlight = 0
const authWaiters = []
let authSpacingChain = Promise.resolve()
let lastAuthStartedAt = 0

async function acquireAuthSlot() {
  while (authInFlight >= AUTH_MAX_CONCURRENT) {
    await new Promise((resolve) => authWaiters.push(resolve))
  }
  authInFlight += 1
}

function releaseAuthSlot() {
  authInFlight -= 1
  const next = authWaiters.shift()
  if (next) {
    next()
  }
}

async function waitAuthSpacing() {
  authSpacingChain = authSpacingChain.then(async () => {
    const spacingWait = lastAuthStartedAt + AUTH_MIN_SPACING_MS - Date.now()
    if (spacingWait > 0) {
      await sleep(spacingWait)
    }
    lastAuthStartedAt = Date.now()
  })
  await authSpacingChain
}

async function passwordGrantWithRetry(supabaseUrl, anonKey, email, password) {
  await acquireAuthSlot()
  try {
    let attempt = 0
    while (true) {
      await waitAuthSpacing()
      const res = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
        method: "POST",
        headers: { apikey: anonKey, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      })
      if (res.ok) {
        const body = await res.json()
        return { token: body.access_token, userId: body.user.id, email }
      }

      const retryAfterMs = res.status === 429 ? parseRetryAfterMs(res) : null
      if (res.status === 429 && attempt < AUTH_MAX_RETRIES) {
        attempt += 1
        const waitMs = authBackoffMs(attempt, retryAfterMs)
        console.warn(
          `  auth 429 ${email} — retry ${attempt}/${AUTH_MAX_RETRIES} in ${Math.round(waitMs / 1000)}s` +
            (retryAfterMs != null ? " (Retry-After)" : "")
        )
        await sleep(waitMs)
        continue
      }

      const detail = await res.text()
      throw new Error(
        `auth failed for ${email}: ${res.status}${detail ? ` ${detail.slice(0, 120)}` : ""}`
      )
    }
  } finally {
    releaseAuthSlot()
  }
}

async function restDelete(supabaseUrl, key, token, table, query) {
  assertScopedQuery(table, query)
  const url = `${supabaseUrl}/rest/v1/${table}?${query}`
  if (dryRun) {
    console.log("[dry-run] DELETE", url)
    return 0
  }
  const res = await fetch(url, {
    method: "DELETE",
    headers: {
      apikey: key,
      Authorization: `Bearer ${token}`,
      Prefer: "return=minimal",
    },
  })
  if (!res.ok && res.status !== 404) {
    const text = await res.text()
    console.warn(`DELETE ${table} ${res.status}: ${text.slice(0, 200)}`)
  }
  return res.status
}

async function softDeleteOwnMessages(supabaseUrl, anonKey, session, conversationIds) {
  for (const cid of conversationIds) {
    const query = `conversation_id=eq.${cid}&sender_id=eq.${session.userId}&content=like.${likeTag}`
    assertScopedQuery("messages", query)
    if (dryRun) {
      console.log("[dry-run] PATCH messages (tagged, fixture conv)", cid)
      continue
    }
    const url = `${supabaseUrl}/rest/v1/messages?${query}`
    const res = await fetch(url, {
      method: "PATCH",
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${session.token}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ deleted_for_everyone: true }),
    })
    if (!res.ok) {
      console.warn(`PATCH messages ${cid}: ${res.status}`)
    }
  }
}

async function deleteOwnRoomMessages(supabaseUrl, anonKey, session, roomIds) {
  for (const rid of roomIds) {
    const query = `room_id=eq.${rid}&user_id=eq.${session.userId}&content=like.${likeTag}`
    await restDelete(supabaseUrl, anonKey, session.token, "room_messages", query)
  }
}

async function serviceRolePurge(supabaseUrl, serviceKey, conversationIds, roomIds) {
  if (process.env.TRADETRAXS_LOADTEST_SERVICE_ROLE_CONFIRM !== "yes") {
    throw new Error(
      "Service-role cleanup requires TRADETRAXS_LOADTEST_SERVICE_ROLE_CONFIRM=yes (still fixture+tag scoped only)"
    )
  }
  for (const cid of conversationIds) {
    const query = `conversation_id=eq.${cid}&content=like.${likeTag}`
    await restDelete(supabaseUrl, serviceKey, serviceKey, "messages", query)
  }
  for (const rid of roomIds) {
    const query = `room_id=eq.${rid}&content=like.${likeTag}`
    await restDelete(supabaseUrl, serviceKey, serviceKey, "room_messages", query)
  }
}

function previewDryRunQueries(user, conversationIds, roomIds) {
  console.log(
    `[dry-run] ${user.email}: ${conversationIds.length} DM PATCH scope(s), ${roomIds.length} room DELETE scope(s) (own rows, tag ${TAG})`
  )
  for (const cid of conversationIds) {
    const query = `conversation_id=eq.${cid}&sender_id=eq.<jwt.sub>&content=like.${likeTag}`
    assertScopedQuery("messages", query.replace("<jwt.sub>", "00000000-0000-4000-8000-000000000000"))
    console.log(`  [dry-run] PATCH messages?${query}`)
  }
  for (const rid of roomIds) {
    const query = `room_id=eq.${rid}&user_id=eq.<jwt.sub>&content=like.${likeTag}`
    assertScopedQuery(
      "room_messages",
      query.replace("<jwt.sub>", "00000000-0000-4000-8000-000000000000")
    )
    console.log(`  [dry-run] DELETE room_messages?${query}`)
  }
}

async function runDryRun(users, conversationIds, roomIds) {
  console.log(
    `[dry-run] ${users.length} accounts — skipping Auth (0 password grants); preview only`
  )
  let idx = 0
  for (const user of users) {
    idx += 1
    if (idx === 1 || idx % 10 === 0 || idx === users.length) {
      console.log(`[dry-run] progress ${idx}/${users.length}`)
    }
    previewDryRunQueries(user, conversationIds, roomIds)
  }
  return users.map((u) => ({ email: u.email, ok: true }))
}

async function cleanupOneUser(supabaseUrl, anonKey, user, conversationIds, roomIds, index, total) {
  const label = `[${index}/${total}] ${user.email}`
  try {
    console.log(`${label} — auth…`)
    const session = await passwordGrantWithRetry(
      supabaseUrl,
      anonKey,
      user.email,
      user.password
    )
    console.log(`${label} — cleanup…`)
    await softDeleteOwnMessages(supabaseUrl, anonKey, session, conversationIds)
    await deleteOwnRoomMessages(supabaseUrl, anonKey, session, roomIds)
    console.log(`${label} — ok`)
    return { email: user.email, ok: true }
  } catch (err) {
    const msg = err.message || String(err)
    console.error(`${label} — failed: ${msg}`)
    return { email: user.email, ok: false, error: msg }
  }
}

async function mapPool(items, concurrency, fn) {
  const results = new Array(items.length)
  let nextIndex = 0

  async function worker() {
    while (nextIndex < items.length) {
      const i = nextIndex
      nextIndex += 1
      results[i] = await fn(items[i], i)
    }
  }

  const workers = []
  for (let w = 0; w < concurrency; w++) {
    workers.push(worker())
  }
  await Promise.all(workers)
  return results
}

function printSummary(results, dryRunMode) {
  const ok = results.filter((r) => r.ok).map((r) => r.email)
  const failed = results.filter((r) => !r.ok)
  console.log("")
  console.log(`${dryRunMode ? "Dry-run" : "Cleanup"} summary:`)
  console.log(`  accounts ok: ${ok.length}`)
  console.log(`  accounts failed: ${failed.length}`)
  if (failed.length) {
    for (const f of failed) {
      console.log(`    - ${f.email}: ${f.error || "unknown"}`)
    }
  }
  if (failed.length) {
    process.exitCode = 1
  }
}

async function main() {
  const supabaseUrl = env("LOADTEST_SUPABASE_URL").replace(/\/+$/, "")
  const anonKey = env("LOADTEST_SUPABASE_ANON_KEY")
  const fixture = loadFixture()
  const { conversationIds, roomIds } = assertFixtureIds(fixture)
  const users = loadUsers()

  console.log(
    `Cleanup profile: ${PROFILE.name} tag=${TAG} conversations=${conversationIds.length} rooms=${roomIds.length} (fixture-only)`
  )
  if (dryRun) {
    console.log("Mode: dry-run (no production mutations, no Auth HTTP)")
  } else {
    console.log(
      `Mode: live — auth spacing=${AUTH_MIN_SPACING_MS}ms concurrency=${AUTH_MAX_CONCURRENT} user_workers=${USER_CLEANUP_CONCURRENCY}`
    )
  }

  const serviceKey = process.env.TRADETRAXS_LOADTEST_SERVICE_ROLE_KEY
  if (serviceKey && !dryRun) {
    console.log("Using service role — only tagged rows in fixture IDs above.")
    await serviceRolePurge(supabaseUrl, serviceKey, conversationIds, roomIds)
    console.log("Done (service role).")
    return
  }
  if (serviceKey && dryRun) {
    console.log("[dry-run] service role path — would DELETE tagged rows in fixture IDs only (no Auth)")
    for (const cid of conversationIds) {
      console.log(`  [dry-run] DELETE messages?conversation_id=eq.${cid}&content=like.${likeTag}`)
    }
    for (const rid of roomIds) {
      console.log(`  [dry-run] DELETE room_messages?room_id=eq.${rid}&content=like.${likeTag}`)
    }
    return
  }

  if (dryRun) {
    const results = await runDryRun(users, conversationIds, roomIds)
    printSummary(results, true)
    return
  }

  console.log("Per-user JWT cleanup — only own sends, tagged, in fixture IDs.")
  const results = await mapPool(users, USER_CLEANUP_CONCURRENCY, (user, i) =>
    cleanupOneUser(supabaseUrl, anonKey, user, conversationIds, roomIds, i + 1, users.length)
  )
  printSummary(results, false)
}

main().catch((err) => {
  console.error(err.message || err)
  process.exit(1)
})
