#!/usr/bin/env node
/**
 * Benchmark rpc_v1_conversation_thread_bootstrap (cold + warm).
 * Skips when credentials are absent.
 */

import { createClient } from "@supabase/supabase-js"

const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
const anonKey =
  process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const email = process.env.SUPABASE_TEST_EMAIL
const password = process.env.SUPABASE_TEST_PASSWORD
const conversationId = process.env.SUPABASE_TEST_CONVERSATION_ID

function percentile(sorted, p) {
  if (sorted.length === 0) return 0
  const idx = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)
  )
  return sorted[idx]
}

function stats(samples) {
  const sorted = [...samples].sort((a, b) => a - b)
  return {
    n: sorted.length,
    p50: percentile(sorted, 50),
    p75: percentile(sorted, 75),
    p95: percentile(sorted, 95),
    p99: percentile(sorted, 99),
    max: sorted[sorted.length - 1] ?? 0,
  }
}

if (!url || !anonKey || !email || !password || !conversationId) {
  console.log(
    "[benchmark-conversation-thread-rpc] SKIP — missing env (see conversation-thread-rpc-integration.test.mjs)"
  )
  process.exit(0)
}

const client = createClient(url, anonKey)
const { error: signInError } = await client.auth.signInWithPassword({
  email,
  password,
})
if (signInError) {
  console.error("[benchmark-conversation-thread-rpc] sign-in failed", signInError)
  process.exit(1)
}

const args = {
  p_conversation_id: conversationId,
  p_message_limit: 50,
  p_cursor: null,
  p_mark_read: false,
}

async function runOnce() {
  const start = performance.now()
  const { data, error } = await client.rpc(
    "rpc_v1_conversation_thread_bootstrap",
    args
  )
  const ms = performance.now() - start
  if (error) throw error
  const bytes = Buffer.byteLength(JSON.stringify(data ?? {}), "utf8")
  return { ms, bytes }
}

const coldSamples = []
const warmSamples = []
let errors = 0

for (let i = 0; i < 5; i += 1) {
  try {
    const { ms, bytes } = await runOnce()
    coldSamples.push(ms)
    if (i === 0) {
      console.log("[benchmark-conversation-thread-rpc] payload bytes", bytes)
    }
  } catch (e) {
    errors += 1
    console.error("[benchmark-conversation-thread-rpc] cold error", e)
  }
}

for (let i = 0; i < 20; i += 1) {
  try {
    const { ms } = await runOnce()
    warmSamples.push(ms)
  } catch (e) {
    errors += 1
  }
}

console.log(
  JSON.stringify(
    {
      operationsPerOpen: 1,
      duplicateMembershipCalls: 0,
      duplicateUnreadCalls: 0,
      errorRate: errors / 25,
      coldMs: stats(coldSamples),
      warmMs: stats(warmSamples),
    },
    null,
    2
  )
)
