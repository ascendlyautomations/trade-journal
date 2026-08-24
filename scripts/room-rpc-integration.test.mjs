#!/usr/bin/env node
/**
 * Phase F room bootstrap integration test — skips when env/credentials missing.
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

loadEnvLocal()

const baseUrl = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
const roomId = process.env.BENCHMARK_ROOM_ID

async function getJwt() {
  if (process.env.BENCHMARK_USER_JWT) return process.env.BENCHMARK_USER_JWT
  if (!baseUrl || !serviceKey) return null
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
  const params = new URLSearchParams(hash)
  return params.get("access_token")
}

async function rpc(jwt, fn, args) {
  const res = await fetch(`${baseUrl.replace(/\/$/, "")}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || serviceKey,
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  })
  const text = await res.text()
  return { ok: res.ok, status: res.status, text }
}

async function main() {
  if (!baseUrl || !roomId) {
    console.log("SKIP: set SUPABASE_URL and BENCHMARK_ROOM_ID for integration test")
    process.exit(0)
  }

  const jwt = await getJwt()
  if (!jwt) {
    console.log("SKIP: no BENCHMARK_USER_JWT and could not mint magic-link JWT")
    process.exit(0)
  }

  let passed = 0
  let failed = 0

  async function check(name, fn) {
    try {
      await fn()
      console.log(`✔ ${name}`)
      passed += 1
    } catch (err) {
      console.error(`✖ ${name}:`, err.message)
      failed += 1
    }
  }

  await check("rpc_v1_room_bootstrap returns contract_version v1", async () => {
    const { ok, text } = await rpc(jwt, "rpc_v1_room_bootstrap", {
      p_room_id: roomId,
      p_message_limit: 25,
      p_mark_read: false,
    })
    if (!ok) throw new Error(text.slice(0, 200))
    const json = JSON.parse(text)
    if (json.meta?.contract_version !== "v1") {
      throw new Error("missing contract_version v1")
    }
    if (!json.data?.room?.id) throw new Error("missing room")
  })

  await check("pagination flag does not mark read in response by default", async () => {
    const { ok, text } = await rpc(jwt, "rpc_v1_room_bootstrap", {
      p_room_id: roomId,
      p_message_limit: 25,
      p_mark_read: false,
    })
    if (!ok) throw new Error(text.slice(0, 200))
    const json = JSON.parse(text)
    if (json.data?.mark_read?.applied !== false) {
      throw new Error("expected mark_read.applied false")
    }
  })

  console.log(`\n${passed} passed, ${failed} failed`)
  process.exit(failed > 0 ? 1 : 0)
}

main()
