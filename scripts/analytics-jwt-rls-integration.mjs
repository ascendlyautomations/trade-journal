/**
 * PostgREST JWT integration checks for analytics RPCs (Calendar V2 QA).
 *
 * Requires:
 *   SUPABASE_URL (or NEXT_PUBLIC_SUPABASE_URL)
 *   SUPABASE_ANON_KEY (or NEXT_PUBLIC_SUPABASE_ANON_KEY)
 *   ANALYTICS_TEST_JWT_USER_A
 *   ANALYTICS_TEST_JWT_USER_B (cross-user isolation)
 *
 * Optional:
 *   ANALYTICS_TEST_USER_B_ID — another user's UUID; User A must not read these stats rows.
 *
 * Skips with exit 0 when JWT env is incomplete.
 */

import fs from "node:fs"
import path from "node:path"

function loadDotEnvLocal() {
  const envPath = path.join(process.cwd(), ".env.local")
  if (!fs.existsSync(envPath)) return
  const text = fs.readFileSync(envPath, "utf8")
  for (const line of text.split("\n")) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith("#")) continue
    const eq = trimmed.indexOf("=")
    if (eq <= 0) continue
    const key = trimmed.slice(0, eq).trim()
    let val = trimmed.slice(eq + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    if (process.env[key] == null || process.env[key] === "") {
      process.env[key] = val
    }
  }
}

loadDotEnvLocal()

const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
const anon =
  process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const jwtA = process.env.ANALYTICS_TEST_JWT_USER_A
const jwtB = process.env.ANALYTICS_TEST_JWT_USER_B
const userBId = process.env.ANALYTICS_TEST_USER_B_ID

if (!url || !anon || !jwtA) {
  console.log(
    "analytics-jwt-rls-integration: SKIP (set SUPABASE_URL, SUPABASE_ANON_KEY, ANALYTICS_TEST_JWT_USER_A)"
  )
  process.exit(0)
}

const rpc = async (jwt, fn, args) => {
  const res = await fetch(`${url}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: anon,
      Authorization: jwt ? `Bearer ${jwt}` : "",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  })
  return { status: res.status, body: await res.text() }
}

const rest = async (jwt, pathAndQuery, init = {}) => {
  const res = await fetch(`${url}/rest/v1/${pathAndQuery}`, {
    ...init,
    headers: {
      apikey: anon,
      Authorization: jwt ? `Bearer ${jwt}` : "",
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  })
  return { status: res.status, body: await res.text() }
}

const start = "2026-09-01"
const end = "2026-09-30"
const sampleDay = "2026-09-04"

let failed = false
const ok = (msg) => console.log(`OK: ${msg}`)
const fail = (msg) => {
  console.error(`FAIL: ${msg}`)
  failed = true
}

// User A — cheap analytical revision RPC (Phase 6E)
const ownRevisionRpc = await rpc(jwtA, "rpc_v1_analytics_revision", {})
if (ownRevisionRpc.status >= 400) {
  fail(`User A analytics revision RPC ${ownRevisionRpc.status} ${ownRevisionRpc.body}`)
} else {
  ok("User A rpc_v1_analytics_revision")
  try {
    const parsed = JSON.parse(ownRevisionRpc.body)
    if (typeof parsed.revision !== "number") {
      fail("analytics revision RPC missing revision number")
    }
  } catch {
    fail("User A analytics revision response not JSON")
  }
}

if (jwtB) {
  const bRevisionRpc = await rpc(jwtB, "rpc_v1_analytics_revision", {})
  if (bRevisionRpc.status >= 400) {
    fail(`User B analytics revision RPC ${bRevisionRpc.status}`)
  } else {
    ok("User B rpc_v1_analytics_revision")
  }
}

const anonRevision = await rpc("", "rpc_v1_analytics_revision", {})
if (anonRevision.status < 400) {
  fail("Anon should not call rpc_v1_analytics_revision")
} else {
  ok("Anon denied rpc_v1_analytics_revision")
}

// User A — dashboard V3
const ownDashboardV3 = await rpc(jwtA, "rpc_v1_analytics_dashboard_bootstrap_v3", {})
if (ownDashboardV3.status >= 400) {
  fail(`User A dashboard V3 ${ownDashboardV3.status} ${ownDashboardV3.body}`)
} else {
  ok("User A dashboard analytics V3 bootstrap")
  try {
    const parsed = JSON.parse(ownDashboardV3.body)
    const presets = parsed.data?.presets ?? parsed.data?.scopes?.[0]?.presets
    if (!presets || !presets.d30) {
      fail("Dashboard V3 missing aggregate presets (d30)")
    }
  } catch {
    fail("User A dashboard V3 response not JSON")
  }
}

// User A — dashboard account charts (owned account required — skip if no accounts in payload)
try {
  const dashParsed = JSON.parse(ownDashboardV3.body)
  const firstAccount = dashParsed.data?.accounts?.[0]?.id
  if (firstAccount) {
    const charts = await rpc(jwtA, "rpc_v1_analytics_dashboard_account_charts_v3", {
      p_account_id: firstAccount,
    })
    if (charts.status >= 400) {
      fail(`User A account charts ${charts.status} ${charts.body}`)
    } else {
      ok("User A dashboard account charts RPC")
    }
  }
} catch {
  fail("Dashboard V3 account charts check failed")
}

// User A — daily range
const ownRange = await rpc(jwtA, "rpc_v1_analytics_daily_range_bootstrap", {
  p_start: start,
  p_end: end,
})
if (ownRange.status >= 400) {
  fail(`User A daily range ${ownRange.status} ${ownRange.body}`)
} else {
  ok("User A daily range bootstrap")
}

// User A — day trades RPC
const ownDay = await rpc(jwtA, "rpc_v1_analytics_calendar_day_trades", {
  p_calendar_day: sampleDay,
})
if (ownDay.status >= 400) {
  fail(`User A day trades ${ownDay.status} ${ownDay.body}`)
} else {
  ok("User A calendar day trades RPC")
  try {
    const parsed = JSON.parse(ownDay.body)
    const agg = parsed.aggregate
    const trades = parsed.trades ?? []
    if (agg && trades.length !== agg.trade_count) {
      fail(
        `Day RPC parity (A): trades.length=${trades.length} aggregate.trade_count=${agg.trade_count}`
      )
    } else if (agg) {
      ok(`Day RPC self-parity on ${sampleDay} (count=${agg.trade_count})`)
    }
  } catch {
    fail("User A day trades response not JSON")
  }
}

// Anon — must not access analytics RPCs
for (const fn of [
  "rpc_v1_analytics_daily_range_bootstrap",
  "rpc_v1_analytics_calendar_day_trades",
  "rpc_v1_analytics_dashboard_bootstrap_v3",
]) {
  const args = fn.includes("day_trades")
    ? { p_calendar_day: sampleDay }
    : fn.includes("dashboard_bootstrap_v3")
      ? {}
      : { p_start: start, p_end: end }
  const anonRes = await rpc("", fn, args)
  if (anonRes.status < 400) {
    fail(`Anon should not call ${fn}: ${anonRes.status}`)
  } else {
    ok(`Anon denied ${fn}`)
  }
}

// User B — own range (if JWT provided)
if (jwtB) {
  const bRange = await rpc(jwtB, "rpc_v1_analytics_daily_range_bootstrap", {
    p_start: start,
    p_end: end,
  })
  if (bRange.status >= 400) {
    fail(`User B own daily range failed ${bRange.status}`)
  } else {
    ok("User B daily range bootstrap")
  }
}

// User A — own user_analytics_state row (SELECT)
const ownRevision = await rest(
  jwtA,
  "user_analytics_state?select=user_id,revision,updated_at&limit=1"
)
if (ownRevision.status >= 400) {
  fail(`User A user_analytics_state SELECT ${ownRevision.status} ${ownRevision.body}`)
} else {
  ok("User A user_analytics_state SELECT own row")
}

// User A cannot UPDATE own revision directly (no UPDATE policy)
let userAId
try {
  const rows = JSON.parse(ownRevision.body)
  userAId = Array.isArray(rows) ? rows[0]?.user_id : null
} catch {
  userAId = null
}
if (userAId) {
  const patchRevision = await rest(
    jwtA,
    `user_analytics_state?user_id=eq.${userAId}`,
    {
      method: "PATCH",
      body: JSON.stringify({ revision: 999999999 }),
      headers: { Prefer: "return=minimal" },
    }
  )
  if (patchRevision.status < 400) {
    fail("User A PATCH user_analytics_state.revision should be denied by RLS")
  } else {
    ok("User A direct revision UPDATE denied")
  }
} else {
  console.log("SKIP: could not resolve User A id for revision PATCH test")
}

if (jwtB) {
  const bOwn = await rest(
    jwtB,
    "user_analytics_state?select=user_id,revision&limit=1"
  )
  let userBIdFromJwt
  try {
    const rows = JSON.parse(bOwn.body)
    userBIdFromJwt = Array.isArray(rows) ? rows[0]?.user_id : null
  } catch {
    userBIdFromJwt = null
  }
  if (userBIdFromJwt) {
    const bPatch = await rest(
      jwtB,
      `user_analytics_state?user_id=eq.${userBIdFromJwt}`,
      {
        method: "PATCH",
        body: JSON.stringify({ revision: 999999999 }),
        headers: { Prefer: "return=minimal" },
      }
    )
    if (bPatch.status < 400) {
      fail("User B PATCH user_analytics_state.revision should be denied")
    } else {
      ok("User B direct revision UPDATE denied")
    }
  }
}

// User A cannot read User B stats rows via REST (RLS)
if (userBId) {
  const cross = await rest(
    jwtA,
    `trade_daily_stats?user_id=eq.${userBId}&select=calendar_day,net_pnl&limit=5`
  )
  if (cross.status >= 400) {
    ok("User A cross-user trade_daily_stats denied or empty (HTTP error)")
  } else {
    try {
      const rows = JSON.parse(cross.body)
      if (Array.isArray(rows) && rows.length > 0) {
        fail(`User A retrieved ${rows.length} trade_daily_stats rows for User B`)
      } else {
        ok("User A cross-user trade_daily_stats empty")
      }
    } catch {
      ok("User A cross-user trade_daily_stats non-JSON (likely denied)")
    }
  }
  const crossRevision = await rest(
    jwtA,
    `user_analytics_state?user_id=eq.${userBId}&select=revision&limit=1`
  )
  if (crossRevision.status >= 400) {
    ok("User A cross-user user_analytics_state denied or empty (HTTP error)")
  } else {
    try {
      const rows = JSON.parse(crossRevision.body)
      if (Array.isArray(rows) && rows.length > 0) {
        fail(`User A retrieved user_analytics_state for User B`)
      } else {
        ok("User A cross-user user_analytics_state empty")
      }
    } catch {
      ok("User A cross-user user_analytics_state non-JSON (likely denied)")
    }
  }
} else {
  console.log("SKIP: ANALYTICS_TEST_USER_B_ID not set (cross-user REST isolation)")
}

console.log(
  "SKIP: Live Supabase Realtime websocket cross-user isolation (requires ANALYTICS_TEST_REALTIME=1 and service-triggered revision bump — not run in default CI)"
)

// User A cannot mutate trade_daily_stats
const patch = await rest(jwtA, "trade_daily_stats?calendar_day=eq.2099-01-01", {
  method: "PATCH",
  body: JSON.stringify({ net_pnl: 0 }),
  headers: { Prefer: "return=minimal" },
})
if (patch.status < 400) {
  fail("User A PATCH trade_daily_stats should be denied")
} else {
  ok("User A mutate trade_daily_stats denied")
}

// Authenticated cannot invoke service-role rebuild RPCs
for (const fn of [
  "rebuild_trade_daily_stats_all_users",
  "rebuild_trade_daily_stats_for_user",
]) {
  const res = await rpc(jwtA, fn, { p_user_id: "00000000-0000-0000-0000-000000000001" })
  if (res.status < 400) {
    fail(`User A should not execute ${fn}`)
  } else {
    ok(`User A denied ${fn}`)
  }
}

process.exit(failed ? 1 : 0)
