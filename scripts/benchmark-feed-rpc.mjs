#!/usr/bin/env node
/**
 * Phase B2 Feed RPC benchmark (local/staging only).
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_ANON_KEY=... BENCHMARK_USER_JWT=... \
 *   node scripts/benchmark-feed-rpc.mjs
 *
 * Runs 30 warm executions per scope/filter combo, reports median/p95/max and payload bytes.
 */

const WARM_RUNS = 30

const SCENARIOS = [
  { label: "following/all", args: { p_scope: "following", p_content_filter: "all", p_limit: 8 } },
  { label: "global/all", args: { p_scope: "global", p_content_filter: "all", p_limit: 8 } },
  { label: "following/trades", args: { p_scope: "following", p_content_filter: "trades", p_limit: 8 } },
  { label: "following/posts", args: { p_scope: "following", p_content_filter: "posts", p_limit: 8 } },
  { label: "following/reels", args: { p_scope: "following", p_content_filter: "reels", p_limit: 8 } },
  { label: "following/achievements", args: { p_scope: "following", p_content_filter: "achievements", p_limit: 8 } },
]

function percentile(sorted, p) {
  if (sorted.length === 0) return 0
  const idx = Math.ceil((p / 100) * sorted.length) - 1
  return sorted[Math.max(0, idx)]
}

async function rpcCall(baseUrl, jwt, args = {}) {
  const url = `${baseUrl.replace(/\/$/, "")}/rest/v1/rpc/rpc_v1_feed_bootstrap`
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
    throw new Error(`rpc_v1_feed_bootstrap HTTP ${res.status}: ${text.slice(0, 300)}`)
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
  const last = samples[samples.length - 1]?.data
  if (last?.data) {
    console.log(`returned: ${last.data.page_meta?.returned ?? "?"} has_more: ${last.data.page_meta?.has_more}`)
    console.log(`next_cursor: ${last.data.next_cursor ?? "null"}`)
  }
}

async function main() {
  const baseUrl = process.env.SUPABASE_URL
  const jwt = process.env.BENCHMARK_USER_JWT
  if (!baseUrl || !jwt) {
    console.error("Set SUPABASE_URL and BENCHMARK_USER_JWT.")
    process.exit(1)
  }

  console.log("Phase B2 Feed RPC benchmark — target:", baseUrl)

  for (const scenario of SCENARIOS) {
    await rpcCall(baseUrl, jwt, scenario.args)
    const samples = []
    for (let i = 0; i < WARM_RUNS; i++) {
      samples.push(await rpcCall(baseUrl, jwt, scenario.args))
    }
    summarize(`rpc_v1_feed_bootstrap (${scenario.label})`, samples)

    const first = samples[0].data
    if (first?.data?.next_cursor) {
      const page2Samples = []
      for (let i = 0; i < 5; i++) {
        page2Samples.push(
          await rpcCall(baseUrl, jwt, {
            ...scenario.args,
            p_cursor: first.data.next_cursor,
          })
        )
      }
      summarize(`rpc_v1_feed_bootstrap (${scenario.label} page 2)`, page2Samples)
    }
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
