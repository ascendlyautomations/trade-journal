#!/usr/bin/env node
/**
 * Adversarial security checks for Explore Mode guest RPCs.
 * Requires .env.local with NEXT_PUBLIC_SUPABASE_URL + NEXT_PUBLIC_SUPABASE_ANON_KEY.
 * Optional: BENCHMARK_USER_JWT (authenticated regression), EXPLORE_PUBLIC_ROOM_ID,
 * EXPLORE_PRIVATE_ROOM_ID, EXPLORE_HIDDEN_ROOM_ID, EXPLORE_FOREIGN_SECTION_ROOM_ID,
 * EXPLORE_FOREIGN_SECTION_ID, EXPLORE_PRIVATE_PROFILE_USERNAME.
 */
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

function loadEnvLocal() {
  try {
    const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
    for (const line of raw.split(/\r?\n/)) {
      const t = line.trim()
      if (!t || t.startsWith("#")) continue
      const eq = t.indexOf("=")
      if (eq <= 0) continue
      const key = t.slice(0, eq).trim()
      let val = t.slice(eq + 1).trim()
      if (
        (val.startsWith('"') && val.endsWith('"')) ||
        (val.startsWith("'") && val.endsWith("'"))
      ) {
        val = val.slice(1, -1)
      }
      if (!process.env[key]) process.env[key] = val
    }
  } catch {
    /* optional */
  }
}

loadEnvLocal()

const baseUrl = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL
const anonKey =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY
const authJwt = process.env.BENCHMARK_USER_JWT

const publicRoomId = process.env.EXPLORE_PUBLIC_ROOM_ID
const privateRoomId = process.env.EXPLORE_PRIVATE_ROOM_ID
const hiddenRoomId = process.env.EXPLORE_HIDDEN_ROOM_ID
const foreignSectionRoomId = process.env.EXPLORE_FOREIGN_SECTION_ROOM_ID
const foreignSectionId = process.env.EXPLORE_FOREIGN_SECTION_ID
const privateProfileUsername = process.env.EXPLORE_PRIVATE_PROFILE_USERNAME

const results = []

function record(name, ok, detail = "") {
  results.push({ name, ok, detail })
  const mark = ok ? "PASS" : "FAIL"
  console.log(`${mark}  ${name}${detail ? ` — ${detail}` : ""}`)
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

async function rpc(fn, body, jwt) {
  const url = `${baseUrl.replace(/\/$/, "")}/rest/v1/rpc/${fn}`
  const res = await fetch(url, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body ?? {}),
  })
  const text = await res.text()
  let data = null
  try {
    data = text ? JSON.parse(text) : null
  } catch {
    data = { raw: text }
  }
  return { status: res.status, data, text }
}

function messageBlob(data) {
  return JSON.stringify(data ?? "").toLowerCase()
}

async function main() {
  if (!baseUrl || !anonKey) {
    console.log("SKIP  missing SUPABASE URL or anon key (.env.local)")
    process.exit(0)
  }

  const anonJwt = anonKey

  // --- anon public feed ---
  {
    const res = await rpc("rpc_v1_feed_bootstrap", { p_scope: "following", p_limit: 8 }, anonJwt)
    const scope = res.data?.data?.scope
    record(
      "anon public feed",
      res.status === 200 && scope === "global",
      `status=${res.status} scope=${scope}`
    )
    const items = res.data?.data?.items ?? []
    const blob = messageBlob(items)
    record(
      "anon feed no achievement account_id leak",
      !blob.includes('"account_id"'),
      `items=${items.length}`
    )
    record(
      "anon feed no copied_account_ids leak",
      !blob.includes("copied_account_ids"),
      `items=${items.length}`
    )
  }

  // --- anon explore ---
  {
    const res = await rpc("rpc_v1_explore_bootstrap", {}, anonJwt)
    record(
      "anon explore bootstrap",
      res.status === 200 && res.data?.meta?.contract_version === "v1",
      `status=${res.status}`
    )
    const rooms = res.data?.data?.rooms ?? []
    record("anon explore returns rooms array", Array.isArray(rooms), `count=${rooms.length}`)
  }

  // --- anon private profile ---
  if (privateProfileUsername) {
    const res = await rpc(
      "rpc_v1_profile_bootstrap",
      { p_username: privateProfileUsername, p_tab: "stats", p_limit: 8 },
      anonJwt
    )
    const restricted =
      res.data?.meta?.found === false ||
      res.data?.data?.viewer?.can_view_full_profile === false ||
      res.data?.data?.profile == null
    record("anon private profile restricted", restricted, privateProfileUsername)
  } else {
    record("anon private profile restricted", true, "SKIP (no EXPLORE_PRIVATE_PROFILE_USERNAME)")
  }

  // --- room guest bootstrap cases ---
  async function guestRoom(roomId, sectionId, label, expectOk) {
    if (!roomId) {
      record(label, true, "SKIP (room id not configured)")
      return
    }
    const body = { p_room_id: roomId, p_limit: 20 }
    if (sectionId) body.p_section_id = sectionId
    const res = await rpc("rpc_v1_public_room_guest_bootstrap", body, anonJwt)
    const blob = messageBlob(res.data)
    const ok = expectOk
      ? res.status === 200 && !blob.includes("seen_by")
      : res.status >= 400 ||
        blob.includes("room_not_public") ||
        blob.includes("room_not_found") ||
        blob.includes("invalid_section")
    record(label, ok, `status=${res.status}`)
    if (expectOk && res.status === 200) {
      const messages = res.data?.data?.messages ?? []
      const mb = messageBlob(messages)
      record(
        `${label}: no seen_by`,
        !mb.includes("seen_by"),
        `messages=${messages.length}`
      )
      record(
        `${label}: reactions aggregated`,
        !mb.includes('"user_id"') || !mb.includes("room_message_reactions"),
        ""
      )
    }
  }

  await guestRoom(publicRoomId, null, "anon public room", true)
  await guestRoom(privateRoomId, null, "anon private room", false)
  await guestRoom(hiddenRoomId, null, "anon hidden room", false)
  await guestRoom(
    "00000000-0000-4000-8000-000000000099",
    null,
    "anon random room UUID",
    false
  )
  await guestRoom(
    foreignSectionRoomId || publicRoomId,
    foreignSectionId,
    "anon public room + foreign section",
    false
  )

  // --- direct member message row must not be callable by anon ---
  {
    const res = await rpc(
      "rpc_v1_room_bootstrap_message_row",
      { p_message_id: "00000000-0000-4000-8000-000000000001" },
      anonJwt
    )
    record(
      "anon cannot execute room_bootstrap_message_row",
      res.status === 401 || res.status === 403 || res.status === 404,
      `status=${res.status}`
    )
  }

  // --- authenticated regression (optional) ---
  if (authJwt) {
    const feed = await rpc(
      "rpc_v1_feed_bootstrap",
      { p_scope: "following", p_limit: 4 },
      authJwt
    )
    record(
      "authenticated feed unchanged",
      feed.status === 200 && feed.data?.data?.scope === "following",
      `status=${feed.status}`
    )
    if (publicRoomId) {
      const room = await rpc(
        "rpc_v1_room_bootstrap",
        { p_room_id: publicRoomId, p_message_limit: 10, p_mark_read: false },
        authJwt
      )
      record(
        "authenticated room bootstrap callable",
        room.status === 200,
        `status=${room.status}`
      )
    } else {
      record("authenticated room bootstrap callable", true, "SKIP (no public room id)")
    }
  } else {
    record("authenticated feed unchanged", true, "SKIP (no BENCHMARK_USER_JWT)")
    record("authenticated room bootstrap callable", true, "SKIP (no BENCHMARK_USER_JWT)")
  }

  const failed = results.filter((r) => !r.ok)
  if (failed.length) {
    console.error(`\n${failed.length} adversarial check(s) failed.`)
    process.exit(1)
  }
  console.log("\nAll adversarial checks passed (or skipped where unconfigured).")
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
