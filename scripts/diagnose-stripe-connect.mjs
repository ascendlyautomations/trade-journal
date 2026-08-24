#!/usr/bin/env node
/**
 * Safe Stripe Connect configuration diagnosis — never prints secrets.
 * Loads .env.local when present. Exits 0 when configured and retrieve succeeds.
 */

import { readFileSync } from "node:fs"
import { resolve } from "node:path"

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

function keyMode(key) {
  if (!key?.trim()) return "missing"
  if (key.startsWith("sk_test_")) return "test"
  if (key.startsWith("sk_live_")) return "live"
  return "invalid"
}

function publishableMode(key) {
  if (!key?.trim()) return "missing"
  if (key.startsWith("pk_test_")) return "test"
  if (key.startsWith("pk_live_")) return "live"
  return "invalid"
}

loadEnvLocal()

const sk = process.env.STRIPE_SECRET_KEY?.trim() ?? ""
const pk = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY?.trim() ?? ""
const baseUrl =
  process.env.SUPABASE_URL?.trim() ||
  process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() ||
  ""
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() ?? ""
const viewerEmail = process.env.BENCHMARK_USER_EMAIL?.trim() || "tradetraxs@gmail.com"

const report = {
  STRIPE_SECRET_KEY_present: Boolean(sk),
  STRIPE_SECRET_KEY_mode: keyMode(sk),
  NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_present: Boolean(pk),
  NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_mode: publishableMode(pk),
  modes_match:
    keyMode(sk) !== "missing" && publishableMode(pk) !== "missing"
      ? keyMode(sk) === publishableMode(pk)
      : null,
  affiliate_row_found: false,
  connected_account_id_present: false,
  account_retrieval_authorized: null,
  connected_account_livemode: null,
  connected_account_belongs_to_platform: null,
  failure_category: null,
}

async function main() {
  if (!sk) {
    report.failure_category = "stripe_not_configured"
    console.log(JSON.stringify(report, null, 2))
    process.exit(1)
  }

  if (keyMode(sk) === "invalid") {
    report.failure_category = "stripe_invalid_format"
    console.log(JSON.stringify(report, null, 2))
    process.exit(1)
  }

  if (!baseUrl || !serviceKey) {
    report.failure_category = "supabase_server_config_missing"
    console.log(JSON.stringify(report, null, 2))
    process.exit(1)
  }

  const { createClient } = await import("@supabase/supabase-js")
  const admin = createClient(baseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: userList, error: userErr } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 200,
  })
  if (userErr) {
    report.failure_category = "supabase_user_lookup_failed"
    console.log(JSON.stringify(report, null, 2))
    process.exit(1)
  }

  const user = userList.users.find(
    (u) => u.email?.toLowerCase() === viewerEmail.toLowerCase()
  )
  if (!user?.id) {
    report.failure_category = "viewer_not_found"
    console.log(JSON.stringify(report, null, 2))
    process.exit(1)
  }

  const { data: affiliate, error: affErr } = await admin
    .from("affiliates")
    .select("id, stripe_connected_account_id")
    .eq("user_id", user.id)
    .maybeSingle()

  if (affErr || !affiliate?.id) {
    report.failure_category = affErr ? "affiliate_lookup_failed" : "affiliate_missing"
    console.log(JSON.stringify(report, null, 2))
    process.exit(1)
  }

  report.affiliate_row_found = true
  const acctId = String(affiliate.stripe_connected_account_id ?? "").trim()
  report.connected_account_id_present = Boolean(acctId)

  if (!acctId) {
    report.failure_category = "connected_account_missing"
    console.log(JSON.stringify(report, null, 2))
    process.exit(0)
  }

  const Stripe = (await import("stripe")).default
  const stripe = new Stripe(sk)

  try {
    const account = await stripe.accounts.retrieve(acctId)
    report.account_retrieval_authorized = true
    report.connected_account_livemode = Boolean(account.livemode)
    report.connected_account_belongs_to_platform = true
    report.failure_category = null
    console.log(JSON.stringify(report, null, 2))
    process.exit(0)
  } catch (err) {
    report.account_retrieval_authorized = false
    report.connected_account_belongs_to_platform = false
    const type = err?.type ?? ""
    if (type === "StripeAuthenticationError" || type === "StripePermissionError") {
      report.failure_category = "stripe_auth_invalid"
    } else if (type === "StripeInvalidRequestError") {
      report.failure_category = "stripe_account_missing"
    } else {
      report.failure_category = "stripe_transient_or_unknown"
    }
    console.log(JSON.stringify(report, null, 2))
    process.exit(1)
  }
}

main().catch((err) => {
  report.failure_category = "unexpected"
  console.log(JSON.stringify(report, null, 2))
  console.error(String(err?.message ?? err))
  process.exit(1)
})
