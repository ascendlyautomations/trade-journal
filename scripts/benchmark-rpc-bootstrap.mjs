#!/usr/bin/env node
/**
 * Phase A RPC bootstrap benchmark (local/staging only).
 *
 * Usage (after applying migration on target DB):
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *   BENCHMARK_USER_JWT=... \
 *   node scripts/benchmark-rpc-bootstrap.mjs
 *
 * Runs 10 warm + 1 cold-ish executions per RPC, reports median/p95/max and payload bytes.
 * Does NOT apply migrations or touch production unless you point env at production.
 */

const WARM_RUNS = 10

function percentile(sorted, p) {
  if (sorted.length === 0) return 0
  const idx = Math.ceil((p / 100) * sorted.length) - 1
  return sorted[Math.max(0, idx)]
}

async function rpcCall(baseUrl, jwt, fn, args = {}) {
  const url = `${baseUrl.replace(/\/$/, "")}/rest/v1/rpc/${fn}`
  const started = performance.now()
  const res = await fetch(url, {
    method: "POST",
    headers: {
      apikey: process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  })
  const text = await res.text()
  const ms = performance.now() - started
  if (!res.ok) {
    throw new Error(`${fn} HTTP ${res.status}: ${text.slice(0, 200)}`)
  }
  return { ms, bytes: Buffer.byteLength(text, "utf8"), data: JSON.parse(text) }
}

function summarize(label, samples) {
  const times = samples.map((s) => s.ms).sort((a, b) => a - b)
  const bytes = samples.map((s) => s.bytes)
  console.log(`\n=== ${label} ===`)
  console.log(`runs: ${samples.length}`)
  console.log(`median ms: ${percentile(times, 50).toFixed(2)}`)
  console.log(`p95 ms: ${percentile(times, 95).toFixed(2)}`)
  console.log(`max ms: ${times[times.length - 1].toFixed(2)}`)
  console.log(`payload bytes (last): ${bytes[bytes.length - 1]}`)
}

async function main() {
  const baseUrl = process.env.SUPABASE_URL
  const jwt = process.env.BENCHMARK_USER_JWT
  if (!baseUrl || !jwt) {
    console.error(
      "Set SUPABASE_URL and BENCHMARK_USER_JWT (authenticated user access token)."
    )
    process.exit(1)
  }

  console.log("Phase A RPC benchmark — target:", baseUrl)

  // Discard first call (connection warm-up)
  await rpcCall(baseUrl, jwt, "rpc_v1_session_bootstrap")
  await rpcCall(baseUrl, jwt, "rpc_v1_dashboard_bootstrap", {
    p_account_id: null,
    p_trade_limit: 500,
  })

  const sessionSamples = []
  const dashboardSamples = []

  for (let i = 0; i < WARM_RUNS; i++) {
    sessionSamples.push(await rpcCall(baseUrl, jwt, "rpc_v1_session_bootstrap"))
    dashboardSamples.push(
      await rpcCall(baseUrl, jwt, "rpc_v1_dashboard_bootstrap", {
        p_account_id: null,
        p_trade_limit: 500,
      })
    )
  }

  summarize("rpc_v1_session_bootstrap", sessionSamples)
  summarize("rpc_v1_dashboard_bootstrap", dashboardSamples)

  const session = sessionSamples[0].data
  const dashboard = dashboardSamples[0].data
  console.log("\nContract sanity:")
  console.log("  session contract_version:", session?.meta?.contract_version)
  console.log("  dashboard contract_version:", dashboard?.meta?.contract_version)
  console.log("  session accounts:", session?.data?.accounts_summary?.length)
  console.log(
    "  dashboard trades:",
    dashboard?.data?.trade_window_meta?.returned
  )
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
