#!/usr/bin/env node
/**
 * Phase E2 Profile RPC benchmark — requires authenticated JWT.
 *
 * Auth (pick one):
 *   PROFILE_TEST_USER_A_JWT=...
 *   PROFILE_TEST_EMAIL=... + service role in .env.local (magic link via profile-test-auth.mjs)
 *
 * Scenarios via env (all required for full matrix):
 *   PROFILE_TEST_PUBLIC_USERNAME      — other public profile with trades
 *   PROFILE_TEST_EMPTY_USERNAME       — public profile without trades
 *   PROFILE_TEST_OWN_USERNAME         — own profile
 *   PROFILE_TEST_PRIVATE_USERNAME     — private followed profile
 *   PROFILE_TEST_RESTRICTED_USERNAME  — private restricted profile
 */

import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

const WARM_RUNS = 50
const COLD_RUNS = 10
const VARIANCE_RUNS = 50
const COLD_IDLE_MS = 15_000

function loadEnvLocal() {
  try {
    const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
    const env = {}
    for (const line of raw.split(/\r?\n/)) {
      if (!line || line.startsWith("#")) continue
      const i = line.indexOf("=")
      if (i < 1) continue
      let val = line.slice(i + 1).trim()
      if (
        (val.startsWith('"') && val.endsWith('"')) ||
        (val.startsWith("'") && val.endsWith("'"))
      ) {
        val = val.slice(1, -1)
      }
      env[line.slice(0, i).trim()] = val
    }
    return env
  } catch {
    return {}
  }
}

function percentile(sorted, p) {
  if (sorted.length === 0) return 0
  const idx = Math.ceil((p / 100) * sorted.length) - 1
  return sorted[Math.max(0, idx)]
}

async function resolveJwt(baseUrl, anonKey, serviceKey) {
  if (process.env.PROFILE_TEST_USER_A_JWT) {
    return process.env.PROFILE_TEST_USER_A_JWT
  }
  const email =
    process.env.PROFILE_TEST_EMAIL ??
    process.env.SUPABASE_TEST_EMAIL ??
    "tradetraxs@gmail.com"
  if (!serviceKey) return null
  const admin = createClient(baseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const anon = createClient(baseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  })
  if (linkErr || !link?.properties?.hashed_token) return null
  const { data: sessionData, error: verifyErr } = await anon.auth.verifyOtp({
    type: "magiclink",
    token_hash: link.properties.hashed_token,
  })
  if (verifyErr || !sessionData.session?.access_token) return null
  return sessionData.session.access_token
}

async function rpc(baseUrl, anonKey, jwt, identifier) {
  const url = `${baseUrl.replace(/\/$/, "")}/rest/v1/rpc/rpc_v1_profile_bootstrap`
  const started = performance.now()
  const res = await fetch(url, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_identifier: identifier,
      p_initial_tab: "trades",
      p_limit: 6,
      p_cursor: null,
    }),
  })
  const text = await res.text()
  const ms = performance.now() - started
  let code = null
  try {
    const parsed = JSON.parse(text)
    code = parsed.code ?? null
  } catch {
    /* non-json */
  }
  return {
    ok: res.ok,
    status: res.status,
    ms,
    bytes: Buffer.byteLength(text, "utf8"),
    code,
    text: text.slice(0, 120),
  }
}

function summarize(label, times, bytes, errors, statuses) {
  const sorted = [...times].sort((a, b) => a - b)
  const pgrst002 = errors.filter((e) => e.code === "PGRST002").length
  const payloadMedian = bytes.length
    ? percentile([...bytes].sort((a, b) => a - b), 50)
    : 0
  const report = {
    label,
    runs_ok: times.length,
    failures: errors.length,
    pgrst002_count: pgrst002,
    status_codes: statuses,
    client_ms: {
      p50: Number(percentile(sorted, 50).toFixed(2)),
      p75: Number(percentile(sorted, 75).toFixed(2)),
      p95: Number(percentile(sorted, 95).toFixed(2)),
      p99: Number(percentile(sorted, 99).toFixed(2)),
      max: Number((sorted[sorted.length - 1] ?? 0).toFixed(2)),
    },
    payload_bytes_median: payloadMedian,
  }
  console.log(JSON.stringify(report, null, 2))
  return report
}

async function runSeries(baseUrl, anonKey, jwt, identifier, runs, idleMs = 0) {
  const times = []
  const bytes = []
  const errors = []
  const statuses = {}
  for (let i = 0; i < runs; i++) {
    if (idleMs > 0 && i > 0) await new Promise((r) => setTimeout(r, idleMs))
    const res = await rpc(baseUrl, anonKey, jwt, identifier)
    statuses[res.status] = (statuses[res.status] ?? 0) + 1
    if (res.ok) {
      times.push(res.ms)
      bytes.push(res.bytes)
    } else {
      errors.push({ status: res.status, code: res.code, ms: res.ms })
    }
  }
  return { times, bytes, errors, statuses }
}

async function main() {
  const localEnv = loadEnvLocal()
  const baseUrl = process.env.SUPABASE_URL ?? localEnv.NEXT_PUBLIC_SUPABASE_URL
  const anonKey =
    process.env.SUPABASE_ANON_KEY ?? localEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const serviceKey = localEnv.SUPABASE_SERVICE_ROLE_KEY

  const jwt = await resolveJwt(baseUrl, anonKey, serviceKey)
  if (!baseUrl || !anonKey || !jwt) {
    console.error(
      "FAIL: requires SUPABASE_URL, SUPABASE_ANON_KEY, and PROFILE_TEST_USER_A_JWT or service role + PROFILE_TEST_EMAIL"
    )
    process.exit(1)
  }

  const scenarios = [
    {
      label: "other_public_with_trades",
      identifier: process.env.PROFILE_TEST_PUBLIC_USERNAME ?? "nrltrades",
      required: true,
    },
    {
      label: "public_no_trades",
      identifier: process.env.PROFILE_TEST_EMPTY_USERNAME ?? "root",
      required: true,
    },
    {
      label: "own_profile",
      identifier: process.env.PROFILE_TEST_OWN_USERNAME ?? "tradetraxs",
      required: true,
    },
    {
      label: "private_followed",
      identifier: process.env.PROFILE_TEST_PRIVATE_USERNAME ?? "blanchettrades",
      required: true,
    },
    {
      label: "private_restricted",
      identifier:
        process.env.PROFILE_TEST_RESTRICTED_USERNAME ?? "blanchettrades",
      jwtOverride: process.env.PROFILE_TEST_ANON_JWT ?? anonKey,
    },
  ]

  console.log("Phase E2 Profile RPC benchmark —", baseUrl)
  const allReports = []

  for (const scenario of scenarios) {
    if (!scenario.identifier) {
      console.error(`FAIL: missing identifier for ${scenario.label}`)
      process.exit(1)
    }
    const scenarioJwt = scenario.jwtOverride ?? jwt

    await rpc(baseUrl, anonKey, scenarioJwt, scenario.identifier)
    const warm = await runSeries(
      baseUrl,
      anonKey,
      scenarioJwt,
      scenario.identifier,
      WARM_RUNS
    )
    allReports.push(
      summarize(
        `${scenario.label}/warm_${WARM_RUNS}`,
        warm.times,
        warm.bytes,
        warm.errors,
        warm.statuses
      )
    )

    const cold = await runSeries(
      baseUrl,
      anonKey,
      scenarioJwt,
      scenario.identifier,
      COLD_RUNS,
      COLD_IDLE_MS
    )
    allReports.push(
      summarize(
        `${scenario.label}/cold_${COLD_RUNS}`,
        cold.times,
        cold.bytes,
        cold.errors,
        cold.statuses
      )
    )

    const variance = await runSeries(
      baseUrl,
      anonKey,
      scenarioJwt,
      scenario.identifier,
      VARIANCE_RUNS
    )
    allReports.push(
      summarize(
        `${scenario.label}/variance_${VARIANCE_RUNS}`,
        variance.times,
        variance.bytes,
        variance.errors,
        variance.statuses
      )
    )
  }

  const totalFailures = allReports.reduce((n, r) => n + r.failures, 0)
  const totalPgrst002 = allReports.reduce((n, r) => n + r.pgrst002_count, 0)
  if (totalFailures > 0 || totalPgrst002 > 0) {
    console.error(
      `FAIL: ${totalFailures} HTTP failures, ${totalPgrst002} PGRST002 responses`
    )
    process.exit(1)
  }

  console.log("\nThresholds: warm p50 < 250ms, warm p95 < 500ms, p99 < 1s")
}

main().catch((err) => {
  console.error("FAIL:", err.message)
  process.exit(1)
})
