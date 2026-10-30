#!/usr/bin/env node
/**
 * Read-only discovery of perf-only DM + room UUIDs for realistic300_full.
 * Throttled password grants (~25 DMs + 1 room check). Does not create rows or send messages.
 */
import { readFileSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { execSync } from "node:child_process"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const specPath = join(root, "fixtures/realistic300-full-isolation.email-spec.json")
const mapPath = join(root, "fixtures/realistic300-full-isolation.uuid-map.json")

const AUTH_SPACING_MS = 1200

function env(name) {
  const v = process.env[name]
  if (!v?.trim()) throw new Error(`Missing ${name}`)
  return v.trim()
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms))
}

function pairKey(a, b) {
  return [a.trim().toLowerCase(), b.trim().toLowerCase()].sort().join("|")
}

function userByEmail(users, email) {
  const needle = email.trim().toLowerCase()
  const u = users.find((x) => x.email.trim().toLowerCase() === needle)
  if (!u) throw new Error(`No password in LOADTEST_USERS_JSON for ${email}`)
  return u
}

async function passwordGrant(supabaseUrl, anonKey, email, password) {
  const res = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  })
  if (!res.ok) {
    const t = await res.text()
    throw new Error(`auth failed ${email}: ${res.status} ${t.slice(0, 120)}`)
  }
  const body = await res.json()
  return { token: body.access_token, userId: body.user.id, email }
}

async function restGet(supabaseUrl, anonKey, token, path) {
  const res = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    headers: { apikey: anonKey, Authorization: `Bearer ${token}`, Accept: "application/json" },
  })
  if (!res.ok) {
    const t = await res.text()
    throw new Error(`GET ${path}: ${res.status} ${t.slice(0, 200)}`)
  }
  return res.json()
}

async function findDmConversationId(supabaseUrl, anonKey, userA, otherUserId) {
  const session = await passwordGrant(supabaseUrl, anonKey, userA.email, userA.password)
  const otherId = otherUserId

  const mine = await restGet(
    supabaseUrl,
    anonKey,
    session.token,
    `conversation_participants?user_id=eq.${session.userId}&select=conversation_id`
  )

  for (const row of mine) {
    const parts = await restGet(
      supabaseUrl,
      anonKey,
      session.token,
      `conversation_participants?conversation_id=eq.${row.conversation_id}&select=user_id`
    )
    const ids = new Set(parts.map((p) => p.user_id))
    if (ids.size === 2 && ids.has(session.userId) && ids.has(otherId)) {
      return row.conversation_id
    }
  }
  return null
}

async function findPerfRoom(supabaseUrl, anonKey, anchorUser, specRoom, emailToUserId) {
  const session = await passwordGrant(
    supabaseUrl,
    anonKey,
    anchorUser.email,
    anchorUser.password
  )
  const perfIds = new Set(Object.values(emailToUserId))
  const mine = await restGet(
    supabaseUrl,
    anonKey,
    session.token,
    `room_members?user_id=eq.${session.userId}&select=room_id`
  )

  for (const row of mine) {
    const members = await restGet(
      supabaseUrl,
      anonKey,
      session.token,
      `room_members?room_id=eq.${row.room_id}&select=user_id`
    )
    const ids = new Set(members.map((m) => m.user_id))
    if (ids.size < specRoom.memberEmails.length - 2) continue
    let allPerf = true
    for (const uid of ids) {
      if (!perfIds.has(uid)) {
        allPerf = false
        break
      }
    }
    if (allPerf && ids.size >= 45) {
      return row.room_id
    }
  }
  return null
}

async function main() {
  const supabaseUrl = env("LOADTEST_SUPABASE_URL").replace(/\/+$/, "")
  const anonKey = env("LOADTEST_SUPABASE_ANON_KEY")
  const users = JSON.parse(env("LOADTEST_USERS_JSON"))
  const spec = JSON.parse(readFileSync(specPath, "utf8"))

  const emailToUserId = {}
  for (let i = 0; i < users.length; i++) {
    if (i > 0) await sleep(AUTH_SPACING_MS)
    const u = users[i]
    const session = await passwordGrant(supabaseUrl, anonKey, u.email, u.password)
    emailToUserId[u.email.trim().toLowerCase()] = session.userId
  }

  const directConversations = {}
  const missingPairs = []

  for (let i = 0; i < spec.directConversationPairs.length; i++) {
    if (i > 0) await sleep(AUTH_SPACING_MS)
    const [emailA, emailB] = spec.directConversationPairs[i]
    const key = pairKey(emailA, emailB)
    const userA = userByEmail(users, emailA)
    const userB = userByEmail(users, emailB)
    const convId = await findDmConversationId(
      supabaseUrl,
      anonKey,
      userA,
      emailToUserId[userB.email.trim().toLowerCase()]
    )
    if (convId) {
      directConversations[key] = convId
      console.log(`found DM ${key} → ${convId}`)
    } else {
      missingPairs.push(key)
    }
  }

  await sleep(AUTH_SPACING_MS)
  const anchor = userByEmail(users, spec.tradeRooms[0].memberEmails[0])
  const roomId = await findPerfRoom(supabaseUrl, anonKey, anchor, spec.tradeRooms[0], emailToUserId)
  const tradeRooms = {}
  if (roomId && spec.tradeRooms[0]) {
    tradeRooms[spec.tradeRooms[0].key] = roomId
    console.log(`found room ${spec.tradeRooms[0].key} → ${roomId}`)
  }

  const map = { directConversations, tradeRooms, tradeRoomSections: {} }
  writeFileSync(mapPath, JSON.stringify(map, null, 2) + "\n")
  console.log(`Wrote ${mapPath}`)

  if (missingPairs.length) {
    console.error("\nMissing DM conversations — create 1:1 chats for:")
    for (const k of missingPairs) console.error("  ", k)
  }
  if (!roomId) {
    console.error("\nMissing private trade room with all perf members (see provision steps)")
  }
  if (missingPairs.length || !roomId) {
    process.exit(2)
  }

  execSync(`node "${join(root, "scripts/assemble-realistic300-full-fixture.mjs")}" --print-env`, {
    stdio: "inherit",
    cwd: root,
  })
}

main().catch((e) => {
  console.error(e.message || e)
  process.exit(1)
})
