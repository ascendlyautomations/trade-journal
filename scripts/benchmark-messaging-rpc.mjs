#!/usr/bin/env node
/**
 * Phase C Messaging RPC benchmark (local/staging only).
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_ANON_KEY=... BENCHMARK_USER_JWT=... \
 *   node scripts/benchmark-messaging-rpc.mjs
 */

const WARM_RUNS = 30

function percentile(sorted, p) {
  if (sorted.length === 0) return 0
  const idx = Math.ceil((p / 100) * sorted.length) - 1
  return sorted[Math.max(0, idx)]
}

async function rpcCall(baseUrl, jwt, name, args = {}) {
  const url = `${baseUrl.replace(/\/$/, "")}/rest/v1/rpc/${name}`
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
    throw new Error(`${name} HTTP ${res.status}: ${text.slice(0, 300)}`)
  }
  return { ms, bytes: Buffer.byteLength(text, "utf8"), data: JSON.parse(text) }
}

function summarize(label, samples) {
  const times = samples.map((s) => s.ms).sort((a, b) => a - b)
  console.log(`\n=== ${label} ===`)
  console.log(`runs: ${samples.length}`)
  console.log(`median ms: ${percentile(times, 50).toFixed(2)}`)
  console.log(`p95 ms: ${percentile(times, 95).toFixed(2)}`)
  console.log(`max ms: ${times[times.length - 1].toFixed(2)}`)
  console.log(`payload bytes (last): ${samples[samples.length - 1]?.bytes ?? 0}`)
}

async function main() {
  const baseUrl = process.env.SUPABASE_URL
  const jwt = process.env.BENCHMARK_USER_JWT
  if (!baseUrl || !jwt) {
    console.error("Set SUPABASE_URL and BENCHMARK_USER_JWT.")
    process.exit(1)
  }

  console.log("Phase C Messaging benchmark — target:", baseUrl)

  const v2Args = {
    p_limit: 40,
    p_cursor: null,
    p_mark_message_notifications_read: false,
  }

  await rpcCall(baseUrl, jwt, "rpc_v2_messaging_bootstrap", v2Args)

  const inboxSamples = []
  for (let i = 0; i < WARM_RUNS; i++) {
    inboxSamples.push(
      await rpcCall(baseUrl, jwt, "rpc_v2_messaging_bootstrap", v2Args)
    )
  }
  summarize("rpc_v2_messaging_bootstrap (inbox)", inboxSamples)

  const combinedSamples = []
  for (let i = 0; i < WARM_RUNS; i++) {
    combinedSamples.push(
      await rpcCall(baseUrl, jwt, "rpc_v2_messaging_bootstrap", {
        p_limit: 40,
        p_cursor: null,
        p_mark_message_notifications_read: true,
      })
    )
  }
  summarize("rpc_v2_messaging_bootstrap (inbox + mark-read)", combinedSamples)

  const v1Samples = []
  for (let i = 0; i < WARM_RUNS; i++) {
    v1Samples.push(
      await rpcCall(baseUrl, jwt, "rpc_v1_messaging_bootstrap", { p_limit: 40 })
    )
  }
  summarize("rpc_v1_messaging_bootstrap (legacy)", v1Samples)

  const first = inboxSamples[0].data
  if (first?.data?.next_cursor) {
    const page2 = []
    for (let i = 0; i < 5; i++) {
      page2.push(
        await rpcCall(baseUrl, jwt, "rpc_v2_messaging_bootstrap", {
          p_limit: 40,
          p_cursor: first.data.next_cursor,
          p_mark_message_notifications_read: false,
        })
      )
    }
    summarize("rpc_v2_messaging_bootstrap (page 2)", page2)
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
