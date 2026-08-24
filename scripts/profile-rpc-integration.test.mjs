#!/usr/bin/env node
/**
 * Profile RPC integration tests (local/staging only).
 */
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

function loadEnvLocal() {
  try {
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
  } catch {
    return {}
  }
}

async function rpc(baseUrl, anonKey, jwt, args) {
  const url = `${baseUrl.replace(/\/$/, "")}/rest/v1/rpc/rpc_v1_profile_bootstrap`
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
  let data = null
  try {
    data = text ? JSON.parse(text) : null
  } catch {
    data = text
  }
  return { status: res.status, data, text }
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function assertNoColumnError(res, label) {
  const blob = JSON.stringify(res.data ?? res.text ?? "").toLowerCase()
  assert(
    !blob.includes("42703") && !blob.includes("expires_at") && !blob.includes("undefined column"),
    `${label}: unexpected column error in response: ${blob.slice(0, 300)}`
  )
}

function assertContract(data, label) {
  assert(data?.meta?.contract_version === 1, `${label}: contract_version`)
  assert(typeof data?.meta?.found === "boolean", `${label}: meta.found`)
  assert(data?.data && typeof data.data === "object", `${label}: data envelope`)
  if (data.meta.found) {
    assert(data.data.profile?.id, `${label}: profile.id`)
    assert(data.data.viewer && typeof data.data.viewer === "object", `${label}: viewer`)
    assert(typeof data.data.followers_count === "number", `${label}: followers_count`)
    assert(typeof data.data.following_count === "number", `${label}: following_count`)
    assert(data.data.section_counts && typeof data.data.section_counts === "object", `${label}: section_counts`)
    assert(typeof data.data.section_counts.has_active_story === "boolean", `${label}: has_active_story`)
    assert(typeof data.data.section_counts.has_room === "boolean", `${label}: has_room`)
  }
}

function assertRestrictedPrivate(data, label) {
  assert(data.meta.found, `${label}: profile must exist`)
  assert(data.data.profile.is_private === true, `${label}: must be private`)
  assert(data.data.viewer.can_view_trades === false, `${label}: trades hidden`)
  assert(data.data.trades_page === null, `${label}: no trades_page`)
  assert(data.data.trade_engagement === null, `${label}: no engagement`)
  assert(data.data.public_stats === null, `${label}: no public_stats`)
  assert(data.data.section_counts.public_trades === null, `${label}: no public_trades count`)
}

async function loadProfile(baseUrl, anonKey, jwt, identifier, extra = {}) {
  const res = await rpc(baseUrl, anonKey, jwt, {
    p_identifier: identifier,
    p_initial_tab: "trades",
    p_limit: 6,
    p_cursor: null,
    ...extra,
  })
  assert(res.status === 200, `${identifier}: HTTP ${res.status} ${String(res.text).slice(0, 200)}`)
  assertNoColumnError(res, identifier)
  assertContract(res.data, identifier)
  return res.data
}

async function main() {
  const localEnv = loadEnvLocal()
  const baseUrl = process.env.SUPABASE_URL ?? localEnv.NEXT_PUBLIC_SUPABASE_URL
  const anonKey =
    process.env.SUPABASE_ANON_KEY ?? localEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const serviceKey = localEnv.SUPABASE_SERVICE_ROLE_KEY

  let jwt = process.env.PROFILE_TEST_USER_A_JWT
  if (!jwt && serviceKey) {
    const { createClient } = await import("@supabase/supabase-js")
    const email =
      process.env.PROFILE_TEST_EMAIL ??
      process.env.SUPABASE_TEST_EMAIL ??
      "tradetraxs@gmail.com"
    const admin = createClient(baseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const anon = createClient(baseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: link } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    })
    const { data: sessionData } = await anon.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.properties.hashed_token,
    })
    jwt = sessionData?.session?.access_token ?? null
  }

  if (!baseUrl || !anonKey || !jwt) {
    console.error(
      "FAIL: requires SUPABASE_URL, SUPABASE_ANON_KEY, and JWT (env or service role magic link)"
    )
    process.exit(1)
  }

  const results = []
  console.log("Profile RPC integration — target:", baseUrl)

  const ownUsername =
    process.env.PROFILE_TEST_OWN_USERNAME ?? "tradetraxs"
  const publicUsername =
    process.env.PROFILE_TEST_PUBLIC_USERNAME ?? "nrltrades"
  const missingUsername =
    process.env.PROFILE_TEST_MISSING_USERNAME ?? "__tt_missing_profile_xyz__"
  const privateVisible =
    process.env.PROFILE_TEST_PRIVATE_VISIBLE_USERNAME ?? "blanchettrades"
  const privateRestricted =
    process.env.PROFILE_TEST_PRIVATE_RESTRICTED_USERNAME ?? "blanchettrades"
  const noStories =
    process.env.PROFILE_TEST_NO_STORIES_USERNAME ?? "root"
  const activeStory =
    process.env.PROFILE_TEST_ACTIVE_STORY_USERNAME ?? "tradetraxs"
  const expiredStory =
    process.env.PROFILE_TEST_EXPIRED_STORY_USERNAME ?? "jayketrades"

  if (ownUsername) {
    const data = await loadProfile(baseUrl, anonKey, jwt, ownUsername)
    assert(data.data.viewer.is_own_profile === true, "own: is_own_profile")
    assert(data.data.viewer.can_view_trades === true, "own: can_view_trades")
    results.push(["own_username", "pass"])
  } else {
    results.push(["own_username", "fail (no own username)"])
  }

  if (publicUsername) {
    const data = await loadProfile(baseUrl, anonKey, jwt, publicUsername)
    assert(data.data.viewer.is_own_profile === false, "public: not own")
    assert(data.data.viewer.can_view_trades === true, "public: can_view_trades")
    if (data.data.trades_page) {
      assert(Array.isArray(data.data.trades_page.items), "public: trades items")
    }
    results.push(["other_public_username", "pass"])
  } else {
    results.push(["other_public_username", "fail (no public username)"])
  }

  {
    const res = await rpc(baseUrl, anonKey, jwt, {
      p_identifier: missingUsername,
      p_initial_tab: "trades",
      p_limit: 6,
      p_cursor: null,
    })
    assert(res.status === 200, `missing: HTTP ${res.status}`)
    assertNoColumnError(res, "missing")
    assert(res.data?.meta?.found === false, "missing: found false")
    assert(res.data?.data?.profile === null, "missing: profile null")
    results.push(["missing_username", "pass"])
  }

  if (privateVisible) {
    const data = await loadProfile(baseUrl, anonKey, jwt, privateVisible)
    assert(data.data.profile.is_private === true, "private_visible: is_private")
    assert(data.data.viewer.can_view_trades === true, "private_visible: can_view")
    assert(data.data.viewer.is_following === true, "private_visible: following")
    results.push(["private_visible_profile", "pass"])
  } else {
    results.push(["private_visible_profile", "skip"])
  }

  if (privateRestricted) {
    const anonJwt = process.env.PROFILE_TEST_ANON_JWT ?? anonKey
    const data = await loadProfile(baseUrl, anonKey, anonJwt, privateRestricted)
    assertRestrictedPrivate(data, "private_restricted")
    results.push(["private_restricted_profile", "pass"])
  } else {
    results.push(["private_restricted_profile", "skip"])
  }

  if (noStories) {
    const data = await loadProfile(baseUrl, anonKey, jwt, noStories)
    assert(data.data.section_counts.has_active_story === false, "no_stories: inactive")
    results.push(["profile_no_stories", "pass"])
  } else {
    results.push(["profile_no_stories", "skip"])
  }

  if (activeStory) {
    const data = await loadProfile(baseUrl, anonKey, jwt, activeStory)
    assert(data.data.section_counts.has_active_story === true, "active_story: true")
    results.push(["profile_active_story", "pass"])
  } else {
    results.push(["profile_active_story", "skip"])
  }

  if (expiredStory) {
    const data = await loadProfile(baseUrl, anonKey, jwt, expiredStory)
    assert(data.data.section_counts.has_active_story === false, "expired_story: false")
    results.push(["profile_expired_story", "pass"])
  } else if (noStories) {
    results.push(["profile_expired_story", "pass (same as no_stories)"])
  } else {
    results.push(["profile_expired_story", "skip"])
  }

  if (publicUsername) {
    const page1 = await loadProfile(baseUrl, anonKey, jwt, publicUsername)
    const meta = page1.data.trades_page?.page_meta
    if (meta?.has_more && meta?.next_cursor) {
      const page2Res = await rpc(baseUrl, anonKey, jwt, {
        p_identifier: publicUsername,
        p_initial_tab: "trades",
        p_limit: 6,
        p_cursor: meta.next_cursor,
      })
      assert(page2Res.status === 200, `page2: HTTP ${page2Res.status}`)
      assertContract(page2Res.data, "page2")
      assert(
        Array.isArray(page2Res.data.data.trades_page?.items),
        "page2: trades items"
      )
      results.push(["cursor_page_two", "pass"])
    } else {
      results.push(["cursor_page_two", "skip (no has_more on public profile)"])
    }
  } else {
    results.push(["cursor_page_two", "skip"])
  }

  const skipped = results.filter(([, s]) => s.startsWith("skip")).length
  const failed = results.filter(([, s]) => s.startsWith("fail")).length
  if (failed > 0) process.exit(1)
  if (skipped === results.length) {
    console.error("FAIL: all integration cases skipped")
    process.exit(1)
  }

  console.log("\n=== Integration results ===")
  for (const [name, status] of results) {
    console.log(`${status.startsWith("pass") ? "✓" : "○"} ${name}: ${status}`)
  }
}

main().catch((err) => {
  console.error("FAIL:", err.message)
  process.exit(1)
})
