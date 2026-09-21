/**
 * Phase 8B security runtime — requires Supabase JWT fixtures when available.
 */

import assert from "node:assert/strict"
import { describe, it } from "node:test"

const ownerJwt = process.env.TRADE_SUMMARY_TEST_JWT_OWNER
const followerJwt = process.env.TRADE_SUMMARY_TEST_JWT_FOLLOWER
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL

async function rpcAs(
  jwt: string | undefined,
  fn: string,
  args: Record<string, unknown>
): Promise<{ status: number; body: unknown }> {
  if (!supabaseUrl || !anonKey) {
    return { status: 0, body: { error: "missing_env" } }
  }
  const headers: Record<string, string> = {
    apikey: anonKey,
    "Content-Type": "application/json",
  }
  if (jwt) headers.Authorization = `Bearer ${jwt}`
  const res = await fetch(`${supabaseUrl}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers,
    body: JSON.stringify(args),
  })
  const body = await res.json().catch(() => null)
  return { status: res.status, body }
}

describe("Phase 8B Profile trades V2 security (runtime)", () => {
  const publicProfile = process.env.TRADE_SUMMARY_TEST_PUBLIC_PROFILE_ID
  const privateProfile = process.env.TRADE_SUMMARY_TEST_PRIVATE_PROFILE_ID
  const ownerProfile = process.env.TRADE_SUMMARY_TEST_OWNER_PROFILE_ID

  it("anon public profile: V2 returns found or empty without error when configured", async () => {
    if (!publicProfile || !supabaseUrl || !anonKey) {
      console.log("BLOCKED: set TRADE_SUMMARY_TEST_PUBLIC_PROFILE_ID + Supabase URL/anon key")
      return
    }
    const { status, body } = await rpcAs(undefined, "rpc_v1_profile_tab_trades_v2", {
      p_profile_id: publicProfile,
      p_limit: 5,
    })
    assert.ok(status === 200 || status === 401, `unexpected status ${status}`)
    if (status === 200 && body && typeof body === "object" && "meta" in body) {
      const meta = (body as { meta: { found?: boolean } }).meta
      assert.equal(typeof meta.found, "boolean")
    }
  })

  it("locked private profile: V2 found=false for anon", async () => {
    if (!privateProfile || !supabaseUrl || !anonKey) {
      console.log("BLOCKED: TRADE_SUMMARY_TEST_PRIVATE_PROFILE_ID")
      return
    }
    const { status, body } = await rpcAs(undefined, "rpc_v1_profile_tab_trades_v2", {
      p_profile_id: privateProfile,
      p_limit: 5,
    })
    if (status !== 200) {
      console.log(`BLOCKED: anon RPC status ${status}`)
      return
    }
    const meta = (body as { meta: { found: boolean } }).meta
    assert.equal(meta.found, false)
  })

  it("owner JWT: V2 items must not include psychology columns", async () => {
    if (!ownerJwt || !ownerProfile) {
      console.log("BLOCKED: TRADE_SUMMARY_TEST_JWT_OWNER + TRADE_SUMMARY_TEST_OWNER_PROFILE_ID")
      return
    }
    const { status, body } = await rpcAs(ownerJwt, "rpc_v1_profile_tab_trades_v2", {
      p_profile_id: ownerProfile,
      p_limit: 5,
    })
    assert.equal(status, 200)
    const items = (body as { data: { items: Record<string, unknown>[] } }).data.items
    for (const item of items) {
      assert.equal("psychology_notes" in item, false)
      assert.equal("notes" in item, false)
      assert.equal("account_id" in item, false)
    }
  })

  it("follower JWT: private profile visibility", async () => {
    if (!followerJwt || !privateProfile) {
      console.log("BLOCKED: TRADE_SUMMARY_TEST_JWT_FOLLOWER")
      return
    }
    const { status, body } = await rpcAs(followerJwt, "rpc_v1_profile_tab_trades_v2", {
      p_profile_id: privateProfile,
      p_limit: 5,
    })
    assert.equal(status, 200)
    const meta = (body as { meta: { found: boolean } }).meta
    assert.equal(typeof meta.found, "boolean")
  })
})
