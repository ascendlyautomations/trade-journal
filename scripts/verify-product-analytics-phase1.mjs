#!/usr/bin/env node
/**
 * Production verification for product analytics phase 1.
 * Loads NEXT_PUBLIC_SUPABASE_* and SUPABASE_SERVICE_ROLE_KEY from .env.local when present.
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
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
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
  console.error("FAIL: missing Supabase URL, anon key, or service role key")
  process.exit(1)
}

const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

const tag = `phase1-verify-${Date.now()}`
const email = `${tag}@tradetraxs-verify.invalid`
const password = `Pw-${randomUUID()}-9a`

let createdUserId = null

async function cleanup() {
  if (!createdUserId) return
  await admin.from("product_events").delete().eq("user_id", createdUserId)
  await admin.from("product_daily_user_activity").delete().eq("user_id", createdUserId)
  await admin.from("product_user_engagement_summary").delete().eq("user_id", createdUserId)
  await admin.auth.admin.deleteUser(createdUserId)
}

async function main() {
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  })
  if (createErr) throw createErr
  createdUserId = created.user.id

  await admin.from("profiles").upsert({ id: createdUserId })

  const userClient = createClient(url, anon)
  const { error: signErr } = await userClient.auth.signInWithPassword({
    email,
    password,
  })
  if (signErr) throw signErr

  const sessionId = randomUUID()
  const dedupe = `${tag}:session`
  const batch = [
    {
      event_name: "session_started",
      platform: "web",
      session_id: sessionId,
      dedupe_key: dedupe,
      props: { screen_id: "dashboard" },
    },
    {
      event_name: "app_opened",
      platform: "web",
      session_id: sessionId,
      dedupe_key: `${tag}:app_open`,
      props: {},
    },
    {
      event_name: "session_started",
      platform: "web",
      session_id: sessionId,
      dedupe_key: dedupe,
      props: {},
    },
  ]

  const { data: ingest, error: ingestErr } = await userClient.rpc(
    "rpc_v1_product_events_ingest",
    { p_batch: batch }
  )
  if (ingestErr) throw ingestErr
  if (ingest?.inserted !== 2 || ingest?.skipped !== 1) {
    throw new Error(
      `unexpected ingest result: ${JSON.stringify(ingest)} (expected inserted=2 skipped=1)`
    )
  }

  const today = new Date().toISOString().slice(0, 10)
  const { data: activity, error: actErr } = await admin
    .from("product_daily_user_activity")
    .select("session_count,app_open_count,engaged,platforms")
    .eq("user_id", createdUserId)
    .eq("activity_day", today)
    .maybeSingle()
  if (actErr) throw actErr
  if (!activity || activity.session_count < 1 || activity.app_open_count < 1) {
    throw new Error(`rollup missing activity row: ${JSON.stringify(activity)}`)
  }
  if (!activity.platforms?.includes("web")) {
    throw new Error(`rollup platforms expected web: ${JSON.stringify(activity)}`)
  }

  const { data: events, error: evErr } = await userClient
    .from("product_events")
    .select("id")
    .limit(1)
  if (evErr) throw evErr
  if ((events ?? []).length > 0) {
    throw new Error("RLS FAIL: user could read product_events rows")
  }

  const { data: rollupLeak, error: rollupErr } = await userClient
    .from("product_daily_user_activity")
    .select("user_id")
    .limit(1)
  if (rollupErr) throw rollupErr
  if ((rollupLeak ?? []).length > 0) {
    throw new Error("RLS FAIL: non-admin could read product_daily_user_activity")
  }

  const other = await admin.from("profiles").select("id").neq("id", createdUserId).limit(1).single()
  if (other.data?.id) {
    const { error: crossErr } = await userClient.from("product_events").insert({
      user_id: other.data.id,
      event_name: "app_opened",
      platform: "web",
      session_id: randomUUID(),
      origin: "user",
      props: {},
    })
    if (!crossErr) {
      throw new Error("RLS FAIL: user inserted event for another user_id")
    }
  }

  const { data: badPlatform, error: badErr } = await userClient.rpc(
    "rpc_v1_product_events_ingest",
    {
      p_batch: [
        {
          event_name: "app_opened",
          platform: "android",
          session_id: randomUUID(),
        },
      ],
    }
  )
  if (badErr) throw badErr
  if (badPlatform?.inserted !== 0 || badPlatform?.skipped !== 1) {
    throw new Error(`bad platform not skipped: ${JSON.stringify(badPlatform)}`)
  }

  console.log("PASS product analytics phase 1 verification")
  console.log(JSON.stringify({ ingest, activity, rls: "denied reads/foreign inserts" }))
}

main()
  .catch((err) => {
    console.error("FAIL:", err.message ?? err)
    process.exitCode = 1
  })
  .finally(() => cleanup())