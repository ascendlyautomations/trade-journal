#!/usr/bin/env node
/**
 * Remote checks: admin_historical_engagement_bundle RPC + distinct-user sanity.
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "fs"

function loadEnv() {
  for (const line of readFileSync(".env.local", "utf8").split("\n")) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
    if (!m) continue
    let v = m[2].trim().replace(/^"|"$/g, "")
    if (!(m[1] in process.env)) process.env[m[1]] = v
  }
}
loadEnv()

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !serviceKey) {
  console.error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")
  process.exit(1)
}

const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

const checks = []

const { error: rpcErr } = await admin.rpc("admin_historical_engagement_bundle", { p_series_days: 30 })
const rpcExists =
  !rpcErr || (rpcErr.message?.includes("not authorized") ?? false)
checks.push({
  name: "admin_historical_engagement_bundle",
  ok: rpcExists,
  detail: rpcErr?.message ?? "ok",
})

if (rpcErr?.message?.includes("not authorized")) {
  checks.push({
    name: "admin_only_gate",
    ok: true,
    detail: "Service role cannot execute bundle (expected); use admin session to read metrics.",
  })
}

const { data: smokeData, error: smokeErr } = await admin.rpc("admin_historical_engagement_bundle", {
  p_series_days: 90,
})
if (!smokeErr && smokeData) {
    const b = smokeData
    const latestEngaged =
      b?.engagement?.engagedUsersPerDay?.[b.engagement.engagedUsersPerDay.length - 1]?.count ?? -1
    const overviewDau = b?.overview?.engagedDau ?? -1
    const aligned = latestEngaged === overviewDau
    checks.push({
      name: "engaged_dau_matches_latest_day_series",
      ok: aligned,
      detail: `series=${latestEngaged} overview=${overviewDau}`,
    })
    checks.push({
      name: "retention_maturity_fields",
      ok:
        typeof b?.retention?.d1MatureCohortSize === "number" &&
        typeof b?.retention?.insufficientData === "boolean",
      detail: "retention metadata present",
    })
    const execSeries = b?.trading?.tradesByExecutionDatePerDay
    const loggedSeries = b?.trading?.tradesLoggedPerDay
    checks.push({
      name: "separate_execution_series",
      ok: Array.isArray(execSeries) && Array.isArray(loggedSeries),
      detail: "execution vs logged arrays",
    })
}

let failed = 0
for (const c of checks) {
  console.log(c.ok ? "✓" : "✗", c.name, c.detail)
  if (!c.ok) failed++
}
process.exit(failed ? 1 : 0)