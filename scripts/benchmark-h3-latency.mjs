#!/usr/bin/env node
/**
 * Final closeout read-only latency benchmark (Staging/local).
 * Uses authenticated user JWT only — never service-role for RPC timing.
 */

import { readFileSync } from "node:fs"
import { resolve } from "node:path"

const WARM_RUNS = 10

function loadEnvLocal() {
  try {
    const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
    for (const line of raw.split("\n")) {
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

function percentile(sorted, p) {
  if (sorted.length === 0) return 0
  const idx = Math.ceil((p / 100) * sorted.length) - 1
  return sorted[Math.max(0, idx)]
}

function summarize(label, samples) {
  const ok = samples.filter((s) => s.ok !== false && !s.error)
  const times = ok.map((s) => s.ms).sort((a, b) => a - b)
  console.log(`\n=== ${label} ===`)
  console.log(`runs: ${samples.length}`)
  console.log(`errors: ${samples.length - ok.length}`)
  if (!times.length) return null
  return {
    label,
    runs: samples.length,
    errors: samples.length - ok.length,
    p50: percentile(times, 50),
    p75: percentile(times, 75),
    p95: percentile(times, 95),
    p99: percentile(times, 99),
    max: times[times.length - 1],
    bytes: ok[ok.length - 1]?.bytes ?? 0,
  }
}

async function getJwt(baseUrl, serviceKey) {
  if (process.env.BENCHMARK_USER_JWT) return process.env.BENCHMARK_USER_JWT
  if (!serviceKey) return null
  const email = process.env.BENCHMARK_USER_EMAIL || "tradetraxs@gmail.com"
  const linkRes = await fetch(`${baseUrl.replace(/\/$/, "")}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "magiclink", email }),
  })
  if (!linkRes.ok) return null
  const linkJson = await linkRes.json()
  const actionLink = linkJson.action_link
  if (!actionLink) return null
  const verifyRes = await fetch(actionLink, { redirect: "manual" })
  const location = verifyRes.headers.get("location") || ""
  const hash = location.split("#")[1] || ""
  return new URLSearchParams(hash).get("access_token")
}

async function restGet(baseUrl, anonKey, jwt, path, query = "") {
  const url = `${baseUrl.replace(/\/$/, "")}/rest/v1/${path}${query}`
  const started = performance.now()
  const res = await fetch(url, {
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${jwt}`,
      Accept: "application/json",
    },
  })
  const text = await res.text()
  return {
    ms: performance.now() - started,
    bytes: Buffer.byteLength(text, "utf8"),
    ok: res.ok,
    status: res.status,
    error: res.ok ? null : text.slice(0, 160),
  }
}

async function rpcCall(baseUrl, anonKey, jwt, fn, args = {}) {
  const url = `${baseUrl.replace(/\/$/, "")}/rest/v1/rpc/${fn}`
  const started = performance.now()
  const res = await fetch(url, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  })
  const text = await res.text()
  return {
    ms: performance.now() - started,
    bytes: Buffer.byteLength(text, "utf8"),
    ok: res.ok,
    status: res.status,
    error: res.ok ? null : text.slice(0, 160),
  }
}

async function runSequential(label, fn, runs = WARM_RUNS) {
  const cold = await fn()
  summarize(`${label} (sequential cold)`, [cold])
  const samples = [cold]
  for (let i = 1; i < runs; i++) {
    samples.push(await fn())
  }
  return summarize(`${label} (sequential warm)`, samples)
}

async function main() {
  loadEnvLocal()
  const baseUrl =
    process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

  if (!baseUrl || !anonKey) {
    console.error("Missing SUPABASE_URL and SUPABASE_ANON_KEY.")
    process.exit(1)
  }

  const jwt = await getJwt(baseUrl, serviceKey)
  if (!jwt) {
    console.error(
      "Missing BENCHMARK_USER_JWT and could not mint authenticated test-user token."
    )
    process.exit(1)
  }

  const tradeIds = (process.env.BENCHMARK_TRADE_IDS ?? "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean)
  const roomId = process.env.BENCHMARK_ROOM_ID?.trim() || null

  console.log("Closeout benchmark — target:", baseUrl)
  console.log("Auth: authenticated test-user JWT (not service-role)")

  const summaries = []

  if (tradeIds.length > 0) {
    const inList = `in.(${tradeIds.join(",")})`
    summaries.push(
      await runSequential("Reels by trade IDs", () =>
        restGet(
          baseUrl,
          anonKey,
          jwt,
          "reels",
          `?select=id,trade_id&trade_id=${inList}`
        )
      )
    )
  } else {
    console.log("\n(skip Reels — set BENCHMARK_TRADE_IDS)")
  }

  summaries.push(
    await runSequential("Feed bootstrap RPC", () =>
      rpcCall(baseUrl, anonKey, jwt, "rpc_v1_feed_bootstrap", {
        p_scope: "global",
      })
    )
  )

  summaries.push(
    await runSequential("Messaging bootstrap RPC", async () => {
      const v2 = await rpcCall(baseUrl, anonKey, jwt, "rpc_v2_messaging_bootstrap", {
        p_limit: 40,
        p_cursor: null,
        p_mark_message_notifications_read: false,
      })
      if (v2.ok) return v2
      return rpcCall(baseUrl, anonKey, jwt, "rpc_v1_messaging_bootstrap", {
        p_limit: 40,
      })
    })
  )

  summaries.push(
    await runSequential("Follower count sample", () =>
      restGet(baseUrl, anonKey, jwt, "followers", "?select=following_id&limit=1")
    )
  )

  summaries.push(
    await runSequential("Trade likes sample", () =>
      restGet(baseUrl, anonKey, jwt, "trade_likes", "?select=id&limit=1")
    )
  )

  summaries.push(
    await runSequential("Trade comments sample", () =>
      restGet(baseUrl, anonKey, jwt, "trade_comments", "?select=id&limit=1")
    )
  )

  summaries.push(
    await runSequential("Room members sample", () =>
      restGet(baseUrl, anonKey, jwt, "room_members", "?select=room_id&limit=1")
    )
  )

  summaries.push(
    await runSequential("Unread counts RPC", () =>
      rpcCall(baseUrl, anonKey, jwt, "get_conversation_unread_counts", {
        p_conversation_ids: [],
      })
    )
  )

  if (roomId) {
    summaries.push(
      await runSequential("Room bootstrap RPC", () =>
        rpcCall(baseUrl, anonKey, jwt, "rpc_v1_room_bootstrap", {
          p_room_id: roomId,
          p_mark_read: false,
        })
      )
    )
  } else {
    console.log("\n(skip Room bootstrap — set BENCHMARK_ROOM_ID)")
  }

  const clusterStarted = performance.now()
  const cluster = await Promise.all([
    tradeIds.length
      ? restGet(
          baseUrl,
          anonKey,
          jwt,
          "reels",
          `?select=id,trade_id&trade_id=in.(${tradeIds.join(",")})`
        )
      : Promise.resolve({ ms: 0, bytes: 0, ok: true, error: null }),
    rpcCall(baseUrl, anonKey, jwt, "rpc_v2_messaging_bootstrap", {
      p_limit: 40,
      p_cursor: null,
      p_mark_message_notifications_read: false,
    }),
    restGet(baseUrl, anonKey, jwt, "followers", "?select=following_id&limit=1"),
    restGet(baseUrl, anonKey, jwt, "trade_likes", "?select=id&limit=1"),
    restGet(baseUrl, anonKey, jwt, "trade_comments", "?select=id&limit=1"),
    restGet(baseUrl, anonKey, jwt, "room_members", "?select=room_id&limit=1"),
  ])
  summarize("HAR cluster simulation (concurrent)", [
    {
      ms: performance.now() - clusterStarted,
      bytes: 0,
      ok: cluster.every((r) => r.ok !== false && !r.error),
      error: null,
    },
    ...cluster,
  ])

  console.log("\n=== Summary table (warm) ===")
  for (const row of summaries.filter(Boolean)) {
    console.log(
      `${row.label}: p50=${row.p50.toFixed(1)} p75=${row.p75.toFixed(1)} p95=${row.p95.toFixed(1)} p99=${row.p99.toFixed(1)} max=${row.max.toFixed(1)} errors=${row.errors}`
    )
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
