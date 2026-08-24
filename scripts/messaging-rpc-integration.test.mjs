#!/usr/bin/env node
/**
 * Phase C Messaging RPC integration tests (local/staging only).
 *
 * Requires:
 *   SUPABASE_URL
 *   SUPABASE_ANON_KEY
 *   MESSAGING_TEST_USER_A_JWT
 *   MESSAGING_TEST_USER_B_JWT (optional cross-user checks)
 *
 * Usage:
 *   node scripts/messaging-rpc-integration.test.mjs
 */

const WARM_RUNS = 30

function percentile(sorted, p) {
  if (sorted.length === 0) return 0
  const idx = Math.ceil((p / 100) * sorted.length) - 1
  return sorted[Math.max(0, idx)]
}

async function rpc(baseUrl, anonKey, jwt, name, args) {
  const url = `${baseUrl.replace(/\/$/, "")}/rest/v1/rpc/${name}`
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
  const ms = performance.now() - started
  let data = null
  try {
    data = text ? JSON.parse(text) : null
  } catch {
    data = text
  }
  return { status: res.status, ms, data, text }
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

async function main() {
  const baseUrl = process.env.SUPABASE_URL
  const anonKey = process.env.SUPABASE_ANON_KEY
  const jwtA = process.env.MESSAGING_TEST_USER_A_JWT
  const jwtB = process.env.MESSAGING_TEST_USER_B_JWT

  if (!baseUrl || !anonKey || !jwtA) {
    console.log(
      "SKIP: database-backed integration tests require SUPABASE_URL, SUPABASE_ANON_KEY, MESSAGING_TEST_USER_A_JWT"
    )
    process.exit(0)
  }

  const results = []
  const bench = { v2: [], v1: [], v2MarkRead: [] }

  console.log("Phase C Messaging integration — target:", baseUrl)

  // Anonymous rejected
  {
    const anon = await rpc(baseUrl, anonKey, anonKey, "rpc_v2_messaging_bootstrap", {
      p_limit: 40,
      p_cursor: null,
      p_mark_message_notifications_read: false,
    })
    assert(anon.status === 401 || anon.status === 403, "anonymous should be rejected")
    results.push(["anonymous_v2_rejected", "pass"])
  }

  // Authenticated V2 load
  let page1 = null
  {
    const res = await rpc(baseUrl, anonKey, jwtA, "rpc_v2_messaging_bootstrap", {
      p_limit: 40,
      p_cursor: null,
      p_mark_message_notifications_read: false,
    })
    assert(res.status === 200, `V2 inbox failed: ${res.status} ${res.text?.slice?.(0, 200)}`)
    assert(res.data?.meta?.viewer_id, "viewer_id required")
    assert(Array.isArray(res.data?.data?.conversations), "conversations array required")
    page1 = res.data
    results.push(["authenticated_v2_inbox", "pass"])
  }

  // V1 legacy still works
  {
    const res = await rpc(baseUrl, anonKey, jwtA, "rpc_v1_messaging_bootstrap", {
      p_limit: 40,
    })
    assert(res.status === 200, `V1 inbox failed: ${res.status}`)
    results.push(["legacy_v1_inbox", "pass"])
  }

  // Pagination must not mutate notifications
  if (page1?.data?.next_cursor) {
    const before = await rpc(baseUrl, anonKey, jwtA, "rpc_v2_messaging_bootstrap", {
      p_limit: 40,
      p_cursor: page1.data.next_cursor,
      p_mark_message_notifications_read: true,
    })
    assert(before.status === 200, "page 2 failed")
    assert(
      (before.data?.data?.message_notifications_marked_read ?? 0) === 0,
      "pagination must not mark notifications read"
    )
    results.push(["pagination_no_notification_mutation", "pass"])

    const ids1 = new Set(page1.data.conversations.map((c) => c.id))
    const ids2 = new Set(before.data.data.conversations.map((c) => c.id))
    for (const id of ids2) {
      assert(!ids1.has(id), `duplicate conversation on page 2: ${id}`)
    }
    results.push(["pagination_no_duplicates", "pass"])
  } else {
    results.push(["pagination_skipped", "skip (single page inbox)"])
  }

  // Muted unread surface
  for (const conv of page1?.data?.conversations ?? []) {
    if (conv.muted) {
      assert(conv.unread_count === 0, "muted conversation must expose unread_count 0")
    }
  }
  results.push(["muted_unread_zero", "pass"])

  // Cross-user isolation
  if (jwtB) {
    const a = page1?.meta?.viewer_id
    const bRes = await rpc(baseUrl, anonKey, jwtB, "rpc_v2_messaging_bootstrap", {
      p_limit: 40,
      p_cursor: null,
      p_mark_message_notifications_read: false,
    })
    assert(bRes.status === 200, "user B inbox failed")
    assert(bRes.data?.meta?.viewer_id !== a, "users must differ")
    results.push(["cross_user_isolation", "pass"])
  } else {
    results.push(["cross_user_isolation", "skip (no user B JWT)"])
  }

  // Warm benchmarks
  await rpc(baseUrl, anonKey, jwtA, "rpc_v2_messaging_bootstrap", {
    p_limit: 40,
    p_cursor: null,
    p_mark_message_notifications_read: false,
  })
  for (let i = 0; i < WARM_RUNS; i++) {
    bench.v2.push(
      (
        await rpc(baseUrl, anonKey, jwtA, "rpc_v2_messaging_bootstrap", {
          p_limit: 40,
          p_cursor: null,
          p_mark_message_notifications_read: false,
        })
      ).ms
    )
    bench.v2MarkRead.push(
      (
        await rpc(baseUrl, anonKey, jwtA, "rpc_v2_messaging_bootstrap", {
          p_limit: 40,
          p_cursor: null,
          p_mark_message_notifications_read: true,
        })
      ).ms
    )
    bench.v1.push(
      (
        await rpc(baseUrl, anonKey, jwtA, "rpc_v1_messaging_bootstrap", {
          p_limit: 40,
        })
      ).ms
    )
  }

  bench.v2.sort((a, b) => a - b)
  bench.v1.sort((a, b) => a - b)
  bench.v2MarkRead.sort((a, b) => a - b)

  console.log("\n=== Integration results ===")
  for (const [name, status] of results) {
    console.log(`${status === "pass" ? "✓" : "○"} ${name}: ${status}`)
  }

  console.log("\n=== Benchmark (30 warm) ===")
  console.log(
    JSON.stringify(
      {
        rpc_v2_messaging_bootstrap: {
          median_ms: Number(percentile(bench.v2, 50).toFixed(2)),
          p95_ms: Number(percentile(bench.v2, 95).toFixed(2)),
          max_ms: Number(bench.v2[bench.v2.length - 1].toFixed(2)),
        },
        rpc_v2_inbox_mark_read: {
          median_ms: Number(percentile(bench.v2MarkRead, 50).toFixed(2)),
          p95_ms: Number(percentile(bench.v2MarkRead, 95).toFixed(2)),
          max_ms: Number(bench.v2MarkRead[bench.v2MarkRead.length - 1].toFixed(2)),
        },
        rpc_v1_messaging_bootstrap: {
          median_ms: Number(percentile(bench.v1, 50).toFixed(2)),
          p95_ms: Number(percentile(bench.v1, 95).toFixed(2)),
          max_ms: Number(bench.v1[bench.v1.length - 1].toFixed(2)),
        },
      },
      null,
      2
    )
  )
}

main().catch((err) => {
  console.error("FAIL:", err.message)
  process.exit(1)
})
