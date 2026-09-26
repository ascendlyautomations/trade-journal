/**
 * Phase A read-only load test for the current TradeTraxs web paths.
 *
 * Does not create trades, comments, likes, follows, messages, or notifications.
 * Refuses to start unless LOADTEST_ENV=staging, and refuses production hosts.
 *
 * First staging run (1 VU, then 10):
 *   set -a && source loadtest/.env && set +a
 *   k6 run loadtest/phase-a-read.js
 */
import http from "k6/http"
import { check, sleep } from "k6"
import exec from "k6/execution"

const PRODUCTION_HOSTS = {
  "tradetraxs.com": true,
  "www.tradetraxs.com": true,
  "app.tradetraxs.com": true,
}
const PRODUCTION_PROJECT_REF = "fobudrkniacatvilbofw"
const SERVICE_ROLE_FRAGMENT = "c2VydmljZV9yb2xl"
const ALLOWED_VUS = { 1: true, 10: true, 25: true, 50: true, 100: true }

const ACCOUNTS_SELECT =
  "id,account_number,name,account_size,mode,category,is_active,can_add_trades,note,consistency,max_drawdown,daily_drawdown,profit_target,winning_days,winning_day_threshold"
const TRADES_ANALYTICS_SELECT =
  "id,user_id,created_at,date,entry_time,exit_time,pnl,rr,direction,ticker,strategy,session,account_id,account_name,account_size,account_type,mode,is_public,public_description,duration_seconds,points,contracts,entry_price,exit_price"
const TRADES_JOURNAL_SELECT =
  "id,user_id,created_at,date,trade_date,pnl,rr,points,contracts,session,ticker,direction,strategy,trade_type,notes,public_description,is_public,is_pinned,image_url,entry_time,exit_time,entry_price,exit_price,duration_seconds,duration_text,account_type,mode,confidence,emotion,followed_plan,mistake_type,market_condition,timeframe,news_event,psychology_notes,reviewed,trade_mode,copied_account_ids,copy_trading_group_id,account_name,account_id,account_size,account_category,top_confluences,is_initial_import,source_account_id,import_source,broker_enrichment_status,broker_lifecycle_id,last_broker_sync_at"
const SESSION_PROFILE_SELECT =
  "id,name,username,onboarding_completed,is_pro,avatar_url"
const PUBLIC_PROFILE_SELECT =
  "id,username,name,bio,avatar_url,trading_style,trader_type,primary_market,started_trading,is_private,created_at"

const config = readConfig()

export const options = {
  discardResponseBodies: true,
  scenarios: {
    phase_a: {
      executor: "ramping-vus",
      stages: stagesFor(config.maxVus),
      gracefulRampDown: "20s",
    },
  },
  summaryTrendStats: ["avg", "p(50)", "p(95)", "p(99)", "count"],
  thresholds: {
    http_req_failed: ["rate<0.01"],
    "http_req_duration{page:session_profile}": ["p(95)<2000"],
    "http_req_duration{page:dashboard_accounts}": ["p(95)<2000"],
    "http_req_duration{page:dashboard_window}": ["p(95)<2000"],
    "http_req_duration{page:dashboard_history}": ["p(95)<5000"],
    "http_req_duration{page:feed}": ["p(95)<2000"],
    "http_req_duration{page:feed_page}": ["p(95)<2000"],
    "http_req_duration{page:profile}": ["p(95)<2000"],
    "http_req_duration{page:trades}": ["p(95)<5000"],
    "http_req_duration{page:leaderboard}": ["p(95)<2000"],
    "http_req_duration{page:messages}": ["p(95)<2000"],
  },
}

let session = null

export default function () {
  const user = config.users[(exec.vu.idInTest - 1) % config.users.length]
  if (!session || session.email !== user.email) {
    session = login(user)
  }
  if (!session) {
    sleep(5)
    return
  }

  const route = exec.vu.idInTest % 5
  if (route === 0) {
    dashboard()
    think()
    feed(false)
    think()
    profile()
    think()
    trades()
  } else if (route === 1) {
    const cursor = feed(true)
    think()
    if (cursor) feedPage(cursor)
    think()
    profile()
  } else if (route === 2) {
    dashboard()
    think()
    trades()
  } else if (route === 3) {
    messages()
  } else {
    dashboard()
    think()
    leaderboard()
  }
  think()
}

function readConfig() {
  if (__ENV.LOADTEST_ENV !== "staging") {
    throw new Error('Refusing to start: set LOADTEST_ENV=staging. Production is blocked.')
  }

  const supabaseUrl = requiredUrl("LOADTEST_SUPABASE_URL")
  const webUrl = requiredUrl("LOADTEST_WEB_URL")
  const anonKey = required("LOADTEST_SUPABASE_ANON_KEY")
  assertNotProduction(supabaseUrl)
  assertNotProduction(webUrl)
  if (anonKey.indexOf(SERVICE_ROLE_FRAGMENT) !== -1 || anonKey.indexOf("service_role") !== -1) {
    throw new Error("Refusing service-role credential.")
  }

  const maxVus = Number(__ENV.LOADTEST_MAX_VUS || 10)
  if (!ALLOWED_VUS[maxVus]) {
    throw new Error("LOADTEST_MAX_VUS must be 1, 10, 25, 50, or 100.")
  }

  const users = JSON.parse(required("LOADTEST_USERS_JSON"))
  if (!Array.isArray(users) || users.length === 0) {
    throw new Error("LOADTEST_USERS_JSON must be a non-empty JSON array.")
  }
  for (let i = 0; i < users.length; i++) {
    if (!users[i] || !users[i].email || !users[i].password) {
      throw new Error("Each load-test user needs email and password.")
    }
  }

  return {
    supabaseUrl: supabaseUrl.replace(/\/+$/, ""),
    webUrl: webUrl.replace(/\/+$/, ""),
    anonKey: anonKey,
    maxVus: maxVus,
    users: users,
  }
}

function stagesFor(maxVus) {
  if (maxVus === 1) {
    return [
      { duration: "30s", target: 1 },
      { duration: "3m", target: 1 },
      { duration: "20s", target: 0 },
    ]
  }
  return [
    { duration: "30s", target: 1 },
    { duration: "2m", target: 1 },
    { duration: "30s", target: maxVus },
    { duration: "4m", target: maxVus },
    { duration: "20s", target: 0 },
  ]
}

function required(name) {
  const value = __ENV[name]
  if (!value || !String(value).trim()) {
    throw new Error("Missing " + name)
  }
  return String(value).trim()
}

function requiredUrl(name) {
  const value = required(name)
  let parsed
  try {
    parsed = new URL(value)
  } catch (error) {
    throw new Error(name + " is not a URL")
  }
  if (parsed.protocol !== "https:") {
    throw new Error(name + " must use https")
  }
  return value
}

function assertNotProduction(rawUrl) {
  const host = new URL(rawUrl).hostname.toLowerCase()
  if (PRODUCTION_HOSTS[host] || rawUrl.indexOf(PRODUCTION_PROJECT_REF) !== -1) {
    throw new Error("Refusing production URL: " + host)
  }
}

function login(user) {
  const res = http.post(
    config.supabaseUrl + "/auth/v1/token?grant_type=password",
    JSON.stringify({ email: user.email, password: user.password }),
    {
      headers: {
        apikey: config.anonKey,
        "Content-Type": "application/json",
      },
      tags: { page: "auth" },
      responseType: "text",
    }
  )
  const ok = check(res, { "auth 200": function (r) { return r.status === 200 } })
  if (!ok) return null
  const body = JSON.parse(res.body)
  if (!body.access_token || !body.user || !body.user.id) return null
  return {
    email: user.email,
    userId: body.user.id,
    token: body.access_token,
  }
}

function headers(token, extra) {
  const base = {
    apikey: config.anonKey,
    Authorization: "Bearer " + token,
    Accept: "application/json",
  }
  if (!extra) return base
  for (const key in extra) base[key] = extra[key]
  return base
}

function restGet(path, page) {
  const res = http.get(config.supabaseUrl + "/rest/v1/" + path, {
    headers: headers(session.token),
    tags: { page: page },
  })
  check(res, { "read 2xx": function (r) { return r.status >= 200 && r.status < 300 } })
  return res
}

function dashboard() {
  const id = encodeURIComponent(session.userId)
  restGet("profiles?id=eq." + id + "&select=" + SESSION_PROFILE_SELECT, "session_profile")
  restGet("accounts?user_id=eq." + id + "&select=" + ACCOUNTS_SELECT, "dashboard_accounts")
  restGet(
    "trades?user_id=eq." + id + "&select=" + TRADES_JOURNAL_SELECT + "&order=created_at.desc&limit=120",
    "dashboard_window"
  )
  thinkShort()
  restGet(
    "trades?user_id=eq." + id + "&select=" + TRADES_ANALYTICS_SELECT + "&order=created_at.desc",
    "dashboard_history"
  )
}

function trades() {
  const id = encodeURIComponent(session.userId)
  restGet(
    "trades?user_id=eq." + id + "&select=" + TRADES_JOURNAL_SELECT + "&order=created_at.desc",
    "trades"
  )
}

function profile() {
  const id = encodeURIComponent(session.userId)
  restGet("profiles?id=eq." + id + "&select=" + PUBLIC_PROFILE_SELECT, "profile")
  const countHeaders = headers(session.token, { Prefer: "count=exact" })
  const followers = http.head(
    config.supabaseUrl + "/rest/v1/followers?following_id=eq." + id + "&select=*",
    { headers: countHeaders, tags: { page: "profile" } }
  )
  const following = http.head(
    config.supabaseUrl + "/rest/v1/followers?follower_id=eq." + id + "&select=*",
    { headers: countHeaders, tags: { page: "profile" } }
  )
  check(followers, { "followers count": function (r) { return r.status >= 200 && r.status < 300 } })
  check(following, { "following count": function (r) { return r.status >= 200 && r.status < 300 } })
  restGet(
    "trades?user_id=eq." + id + "&select=id,created_at,pnl,rr,mode,account_type&is_public=eq.true&order=created_at.desc&limit=6",
    "profile"
  )
}

function feed(keepBody) {
  const res = http.post(
    config.supabaseUrl + "/rest/v1/rpc/rpc_v1_feed_bootstrap",
    JSON.stringify({
      p_scope: "global",
      p_content_filter: "all",
      p_limit: 8,
    }),
    {
      headers: headers(session.token, { "Content-Type": "application/json" }),
      tags: { page: "feed" },
      responseType: keepBody ? "text" : "none",
    }
  )
  check(res, { "feed 200": function (r) { return r.status === 200 } })
  if (!keepBody || res.status !== 200 || !res.body) return null
  try {
    const payload = JSON.parse(res.body)
    const cursor = payload && payload.data ? payload.data.next_cursor : null
    return cursor || null
  } catch (error) {
    return null
  }
}

function feedPage(cursor) {
  const res = http.post(
    config.supabaseUrl + "/rest/v1/rpc/rpc_v1_feed_bootstrap",
    JSON.stringify({
      p_scope: "global",
      p_content_filter: "all",
      p_limit: 8,
      p_cursor: cursor,
    }),
    {
      headers: headers(session.token, { "Content-Type": "application/json" }),
      tags: { page: "feed_page" },
    }
  )
  check(res, { "feed page 200": function (r) { return r.status === 200 } })
}

function messages() {
  const res = http.post(
    config.supabaseUrl + "/rest/v1/rpc/rpc_v2_messaging_bootstrap",
    JSON.stringify({
      p_limit: 40,
      p_cursor: null,
      p_mark_message_notifications_read: false,
    }),
    {
      headers: headers(session.token, { "Content-Type": "application/json" }),
      tags: { page: "messages" },
    }
  )
  check(res, { "messages 200": function (r) { return r.status === 200 } })
}

function leaderboard() {
  const params = [
    "view=7D",
    "account=all",
    "now=" + encodeURIComponent(new Date().toISOString()),
    "viewer=" + encodeURIComponent(session.userId),
  ].join("&")
  const res = http.get(config.webUrl + "/api/leaderboard/trades?" + params, {
    tags: { page: "leaderboard" },
  })
  check(res, { "leaderboard 200": function (r) { return r.status === 200 } })
}

function think() {
  sleep(3 + Math.random() * 5)
}

function thinkShort() {
  sleep(0.4 + Math.random() * 0.6)
}
