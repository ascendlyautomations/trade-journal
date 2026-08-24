#!/usr/bin/env node
/**
 * Phase F Room bootstrap RPC benchmark (local/staging only).
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_ANON_KEY=... BENCHMARK_USER_JWT=... BENCHMARK_ROOM_ID=... \
 *   node scripts/benchmark-room-rpc.mjs
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
      apikey:
        process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY,
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
  return { ms, bytes: Buffer.byteLength(text, "utf8") }
}

function summarize(label, samples) {
  const times = samples.map((s) => s.ms).sort((a, b) => a - b)
  console.log(`\n=== ${label} ===`)
  console.log(`runs: ${samples.length}`)
  console.log(`p50 ms: ${percentile(times, 50).toFixed(2)}`)
  console.log(`p75 ms: ${percentile(times, 75).toFixed(2)}`)
  console.log(`p95 ms: ${percentile(times, 95).toFixed(2)}`)
  console.log(`p99 ms: ${percentile(times, 99).toFixed(2)}`)
  console.log(`max ms: ${times[times.length - 1].toFixed(2)}`)
  console.log(`payload bytes (last): ${samples[samples.length - 1]?.bytes ?? 0}`)
}

async function main() {
  const baseUrl = process.env.SUPABASE_URL
  const jwt = process.env.BENCHMARK_USER_JWT
  const roomId = process.env.BENCHMARK_ROOM_ID
  if (!baseUrl || !jwt || !roomId) {
    console.error("Set SUPABASE_URL, BENCHMARK_USER_JWT, and BENCHMARK_ROOM_ID.")
    process.exit(1)
  }

  console.log("Phase F Room benchmark — target:", baseUrl, "room:", roomId)

  const args = {
    p_room_id: roomId,
    p_section_id: null,
    p_message_limit: 25,
    p_mark_read: false,
  }

  await rpcCall(baseUrl, jwt, "rpc_v1_room_bootstrap", args)

  const warm = []
  for (let i = 0; i < WARM_RUNS; i++) {
    warm.push(await rpcCall(baseUrl, jwt, "rpc_v1_room_bootstrap", args))
  }
  summarize("rpc_v1_room_bootstrap (warm, no mark_read)", warm)

  const markRead = []
  for (let i = 0; i < 10; i++) {
    markRead.push(
      await rpcCall(baseUrl, jwt, "rpc_v1_room_bootstrap", {
        ...args,
        p_mark_read: true,
      })
    )
  }
  summarize("rpc_v1_room_bootstrap (mark_read=true)", markRead)

  console.log("\nTarget (staging): warm p50 < 250ms, warm p95 < 500ms")
  console.log("requests per intentional room open (V2): 1 bootstrap + 1 presence")
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
