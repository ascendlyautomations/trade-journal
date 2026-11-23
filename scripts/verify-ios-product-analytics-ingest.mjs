#!/usr/bin/env node
/**
 * Verifies iOS-shaped payloads ingest to production (platform=ios, auth required).
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync, existsSync } from "node:fs"
import { randomUUID } from "node:crypto"

function loadEnvLocal() {
  const path = new URL("../.env.local", import.meta.url)
  if (!existsSync(path)) return
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
    if (!m) continue
    let v = m[2].trim()
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1)
    }
    if (!(m[1] in process.env)) process.env[m[1]] = v
  }
}

loadEnvLocal()

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !anon || !serviceKey) {
  console.error("FAIL: missing env")
  process.exit(1)
}

const tag = `ios-verify-${Date.now()}`
const email = `${tag}@tradetraxs-verify.invalid`
const password = `Pw-${randomUUID()}-9a`
let userId = null

const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

async function cleanup() {
  if (!userId) return
  await admin.from("product_events").delete().eq("user_id", userId)
  await admin.from("product_daily_user_activity").delete().eq("user_id", userId)
  await admin.auth.admin.deleteUser(userId)
}

async function main() {
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  })
  if (createErr) throw createErr
  userId = created.user.id
  await admin.from("profiles").upsert({ id: userId })

  const userClient = createClient(url, anon)
  const { error: signErr } = await userClient.auth.signInWithPassword({ email, password })
  if (signErr) throw signErr

  const sessionId = randomUUID()
  const batch = [
    {
      event_name: "session_started",
      platform: "ios",
      session_id: sessionId,
      dedupe_key: `${tag}:session`,
    },
    {
      event_name: "app_opened",
      platform: "ios",
      session_id: sessionId,
      dedupe_key: `${tag}:open`,
    },
    {
      event_name: "screen_viewed",
      platform: "ios",
      session_id: sessionId,
      dedupe_key: `${tag}:screen`,
      props: { screen_id: "dashboard" },
    },
  ]

  const { data: ingest, error: ingestErr } = await userClient.rpc("rpc_v1_product_events_ingest", {
    p_batch: batch,
  })
  if (ingestErr) throw ingestErr

  const { count, error: countErr } = await admin
    .from("product_events")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("platform", "ios")
  if (countErr) throw countErr

  const { data: rollup } = await admin
    .from("product_daily_user_activity")
    .select("engaged,platforms,session_count")
    .eq("user_id", userId)
    .maybeSingle()

  console.log(
    JSON.stringify({
      project: url,
      ingest,
      iosEventsStored: count,
      rollup,
    })
  )

  if ((count ?? 0) < 3 || !rollup?.engaged) {
    console.error("FAIL: iOS ingest or rollup engaged flag")
    process.exit(1)
  }
  console.log("PASS ios product analytics ingest")
}

main()
  .catch((e) => {
    console.error("FAIL", e)
    process.exit(1)
  })
  .finally(cleanup)