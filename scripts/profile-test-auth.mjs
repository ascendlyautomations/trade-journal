#!/usr/bin/env node
/**
 * Resolve PROFILE_TEST_USER_A_JWT via service-role magic link (no password in repo).
 * Prints nothing to stdout except the access token when PROFILE_TEST_AUTH_QUIET=1
 * is unset; use eval/export in shell wrappers only.
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

function loadEnvLocal() {
  const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
  const env = {}
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue
    const i = line.indexOf("=")
    if (i < 1) continue
    let val = line.slice(i + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    env[line.slice(0, i).trim()] = val
  }
  return env
}

const env = loadEnvLocal()
const url = process.env.SUPABASE_URL ?? env.NEXT_PUBLIC_SUPABASE_URL
const anonKey =
  process.env.SUPABASE_ANON_KEY ?? env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY
const email =
  process.env.PROFILE_TEST_EMAIL ??
  process.env.SUPABASE_TEST_EMAIL ??
  "tradetraxs@gmail.com"

if (!url || !anonKey || !serviceKey) {
  console.error("Missing Supabase URL, anon key, or service role key in .env.local")
  process.exit(1)
}

const admin = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const anon = createClient(url, anonKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
  type: "magiclink",
  email,
})
if (linkErr || !link?.properties?.hashed_token) {
  console.error("generateLink failed:", linkErr?.message ?? "no token")
  process.exit(1)
}

const { data: sessionData, error: verifyErr } = await anon.auth.verifyOtp({
  type: "magiclink",
  token_hash: link.properties.hashed_token,
})
if (verifyErr || !sessionData.session?.access_token) {
  console.error("verifyOtp failed:", verifyErr?.message ?? "no session")
  process.exit(1)
}

const token = sessionData.session.access_token
if (process.env.PROFILE_TEST_AUTH_QUIET === "1") {
  process.stdout.write(token)
} else {
  console.log("JWT resolved for", email, "(token omitted)")
}
