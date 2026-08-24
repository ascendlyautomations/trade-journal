#!/usr/bin/env node
/**
 * Warm benchmark for rpc_v1_getting_started_signals (local/staging only).
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_ANON_KEY=... \
 *   SUPABASE_TEST_EMAIL=... SUPABASE_TEST_PASSWORD=... \
 *   node scripts/benchmark-getting-started-rpc.mjs
 */

import { createClient } from "@supabase/supabase-js"

const url = process.env.SUPABASE_URL
const anonKey = process.env.SUPABASE_ANON_KEY
const email = process.env.SUPABASE_TEST_EMAIL
const password = process.env.SUPABASE_TEST_PASSWORD
const iterations = Number(process.env.BENCHMARK_ITERATIONS ?? 30)

if (!url || !anonKey || !email || !password) {
  console.error(
    "Missing SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_TEST_EMAIL, or SUPABASE_TEST_PASSWORD"
  )
  process.exit(1)
}

const supabase = createClient(url, anonKey)
const { error: signInError } = await supabase.auth.signInWithPassword({
  email,
  password,
})
if (signInError) {
  console.error("signIn failed:", signInError.message)
  process.exit(1)
}

const { data: probe, error: probeError } = await supabase.rpc(
  "rpc_v1_getting_started_signals",
  {}
)
if (probeError) {
  console.error("RPC probe failed:", probeError.message, probeError.code)
  process.exit(1)
}

console.log("Sample payload keys:", Object.keys(probe ?? {}))

const { data: explainRows, error: explainError } = await supabase.rpc(
  "rpc_v1_getting_started_signals",
  {}
)
if (explainError) {
  console.warn("Could not fetch for EXPLAIN note:", explainError.message)
}

console.log(
  "\nRun EXPLAIN locally against staging:\n  explain (verbose, costs off) select public.rpc_v1_getting_started_signals();\n"
)

const samples = []
for (let i = 0; i < iterations; i += 1) {
  const start = performance.now()
  const { error } = await supabase.rpc("rpc_v1_getting_started_signals", {})
  const ms = performance.now() - start
  if (error) {
    console.error("iteration failed:", error.message)
    process.exit(1)
  }
  samples.push(ms)
}

samples.sort((a, b) => a - b)
const median = samples[Math.floor(samples.length / 2)]
const p95 = samples[Math.floor(samples.length * 0.95)]
const max = samples[samples.length - 1]

console.log(`Iterations: ${iterations}`)
console.log(`Median ms: ${median.toFixed(2)}`)
console.log(`P95 ms: ${p95.toFixed(2)}`)
console.log(`Max ms: ${max.toFixed(2)}`)
