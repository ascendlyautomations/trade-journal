#!/usr/bin/env node
/**
 * Remote checks: phase 1 tables, preview allow-list, admin_product_analytics_bundle RPC.
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync, existsSync } from "node:fs"

function loadEnvLocal() {
  const path = new URL("../.env.local", import.meta.url)
  if (!existsSync(path)) return
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
    if (!m) continue
    let v = m[2].trim()
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1)
    }
    if (!(m[1] in process.env)) process.env[m[1]] = v
  }
}

loadEnvLocal()

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) {
  console.error("FAIL: missing Supabase URL or service role key")
  process.exit(1)
}

const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

async function main() {
  const checks = []

  const { data: allowed, error: allowErr } = await admin.rpc("product_analytics_allowed_event_names")
  checks.push({
    name: "product_analytics_allowed_event_names",
    ok: !allowErr && Array.isArray(allowed) && allowed.includes("traxspro_preview_started"),
    detail: allowErr?.message ?? `events=${allowed?.length}`,
  })

  const { error: rollupErr } = await admin.from("product_daily_user_activity").select("activity_day").limit(1)
  checks.push({
    name: "product_daily_user_activity",
    ok: !rollupErr,
    detail: rollupErr?.message ?? "readable",
  })

  const { error: rpcErr } = await admin.rpc("admin_product_analytics_bundle", { p_series_days: 7 })
  checks.push({
    name: "admin_product_analytics_bundle",
    ok: !rpcErr,
    detail: rpcErr?.message ?? "callable",
  })

  const failed = checks.filter((c) => !c.ok)
  if (failed.length) {
    console.error("FAIL admin product analytics phase 2 verification")
    for (const c of failed) console.error(` - ${c.name}: ${c.detail}`)
    process.exit(1)
  }

  console.log("PASS admin product analytics phase 2 verification")
  for (const c of checks) console.log(` ${c.name}: ${c.detail}`)
}

main().catch((e) => {
  console.error("FAIL", e)
  process.exit(1)
})