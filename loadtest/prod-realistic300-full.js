/**
 * Production realistic300_full — iOS reads + isolated DM/room writes + Realtime.
 *
 * Separate from loadtest/prod-read-perf.js (read-only modes unchanged).
 *
 * Gates:
 *   LOADTEST_ENV=production
 *   TRADETRAXS_PROD_PERF_CONFIRM=yes
 *   TRADETRAXS_PROD_PERF_REALISTIC300_FULL=yes
 *   LOADTEST_REALISTIC300_FULL_FIXTURE_JSON — isolation fixture (see fixtures/)
 *
 * Do not run without reviewing loadtest/docs/PROD_PERF_REALISTIC300_FULL.md
 */
import { sleep } from "k6"
import exec from "k6/execution"
import { Trend } from "k6/metrics"
import { recordHttpOutcome } from "./lib/k6-diagnostics.js"
import { PRODUCTION_PROJECT_REF, REQUEST_TIMEOUT, STAGING_PROJECT_REF } from "./lib/constants.js"
import { parseHttpsUrl, requiredEnv, requiredHttpsUrl } from "./lib/k6-shared.js"
import {
  appendEndpointLatency,
  appendFeedCursorLatency,
  appendHttpAggregate,
  appendHttpOutcomeCounters,
  appendOkDurationByPage,
  appendRunTimingBreakdown,
  appendThresholdResults,
  appendRealistic300FullMetrics,
  snapshotRealistic300FullMetrics,
} from "./lib/k6-summary.js"
import { formatSetupAuthFailure } from "./lib/auth-grant-diagnostics.js"
import {
  loginPasswordGrant,
  loginPasswordGrantDetailedWithRetry,
  runProductionReadPreflight,
} from "./lib/read-workload-prod.js"
import { runRealistic300FullIteration } from "./lib/read-workload-realistic300-full.js"
import {
  fixtureEmailsLower,
  parseRealistic300FullFixture,
} from "./lib/realistic300-full-fixture.js"
import { applyStageStartJitter } from "./lib/vu-jitter.js"
import { parseGlobalSendCaps } from "./lib/realistic300-full-send-budget.js"

const SERVICE_ROLE_FRAGMENT = "c2VydmljZV9yb2xl"
const ALLOWED_WEB_HOSTS = {
  "tradetraxs.com": true,
  "www.tradetraxs.com": true,
  "app.tradetraxs.com": true,
}

const MAX_VUS = 300
const SETUP_AUTH_SPACING_SEC = 0.85
const setupWallMs = new Trend("tradetraxs_setup_wall_ms", true)

const config = readConfig()

globalThis.__recordHttpOutcome = recordHttpOutcome

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ["avg", "p(50)", "p(95)", "p(99)", "count"],
  scenarios: {
    realistic300_full: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "3m", target: MAX_VUS },
        { duration: "10m", target: MAX_VUS },
        { duration: "1m", target: 0 },
      ],
      gracefulRampDown: "2m",
      tags: { workload: "realistic300_full_ios" },
    },
  },
  thresholds: {
    http_req_failed: [{ threshold: "rate<0.02", abortOnFail: true }],
    http_req_duration: [{ threshold: "p(95)<8000", abortOnFail: true }],
    "http_req_duration{page:dashboard_rpc}": [{ threshold: "p(95)<5000", abortOnFail: true }],
    "http_req_duration{page:feed}": [{ threshold: "p(95)<5000", abortOnFail: true }],
    "http_req_duration{page:feed_page}": [{ threshold: "p(95)<5000", abortOnFail: true }],
  },
}

export function setup() {
  const setupStarted = Date.now()
  const fixture = parseRealistic300FullFixture(requiredEnv("LOADTEST_REALISTIC300_FULL_FIXTURE_JSON"))
  const fixtureEmailSet = fixtureEmailsLower(fixture)

  const sessionsByEmail = {}
  for (let i = 0; i < config.users.length; i++) {
    if (i > 0) {
      sleep(SETUP_AUTH_SPACING_SEC)
    }
    const user = config.users[i]
    const emailLower = String(user.email).trim().toLowerCase()
    if (!fixtureEmailSet[emailLower]) {
      throw new Error(
        "Fixture isolation: user " + user.email + " is not a participant in any fixture DM/room"
      )
    }
    const grant = loginPasswordGrantDetailedWithRetry(
      config.supabaseUrl,
      config.anonKey,
      user,
      "setup_auth"
    )
    if (!grant.session) {
      throw new Error(formatSetupAuthFailure(i, user.email, grant.failure, grant.retryMeta))
    }
    sessionsByEmail[user.email] = {
      email: grant.session.email,
      userId: grant.session.userId,
      token: grant.session.token,
    }
  }

  const preflightSession = sessionsByEmail[config.users[0].email]
  runProductionReadPreflight(config.supabaseUrl, config.anonKey, preflightSession)

  setupWallMs.add(Date.now() - setupStarted)
  return {
    preflight: "ok",
    mode: "realistic300_full",
    fixtureTag: fixture.tag,
    fixture: fixture,
    sessionsByEmail: sessionsByEmail,
    vuUserIndex: buildVuUserIndex(MAX_VUS, config.users.length),
  }
}

function buildVuUserIndex(maxVus, userCount) {
  const indices = []
  for (let vu = 1; vu <= maxVus; vu++) {
    indices.push((vu * 48271 + 104729) % userCount)
  }
  return indices
}

let vuSession = null
let vuSessionEmail = null
let vuAuthRefreshNotBefore = 0
let activeScenario = null
const AUTH_REFRESH_COOLDOWN_MS = 30000

function resolveUserForVu(data, vuId) {
  if (data.vuUserIndex && data.vuUserIndex.length >= vuId) {
    return config.users[data.vuUserIndex[vuId - 1]]
  }
  return config.users[(vuId - 1) % config.users.length]
}

function cloneSessionFromSetup(seed) {
  return { email: seed.email, userId: seed.userId, token: seed.token }
}

function refreshSessionThrottled(user) {
  const now = Date.now()
  if (now < vuAuthRefreshNotBefore) {
    return null
  }
  sleep(Math.random() * 2)
  vuAuthRefreshNotBefore = now + AUTH_REFRESH_COOLDOWN_MS + Math.floor(Math.random() * 5000)
  const refreshed = loginPasswordGrant(config.supabaseUrl, config.anonKey, user, "auth_refresh")
  if (refreshed) {
    vuSession = refreshed
    vuSessionEmail = user.email
  }
  return refreshed
}

function resolveSession(data, user) {
  if (vuSession && vuSessionEmail === user.email) {
    return vuSession
  }
  const seed = data.sessionsByEmail && data.sessionsByEmail[user.email]
  if (seed && seed.token) {
    vuSession = cloneSessionFromSetup(seed)
    vuSessionEmail = user.email
    return vuSession
  }
  return refreshSessionThrottled(user)
}

export default function (data) {
  const scen = exec.scenario.name
  if (scen !== activeScenario) {
    activeScenario = scen
    applyStageStartJitter(exec.vu.idInTest, MAX_VUS, config.vuStartJitterSec)
  }

  const user = resolveUserForVu(data, exec.vu.idInTest)
  const session = resolveSession(data, user)
  if (!session) {
    sleep(4)
    return
  }

  const ctx = {
    feedScope: config.feedScope,
    sendCaps: config.sendCaps,
  }

  try {
    runRealistic300FullIteration(
      config.supabaseUrl,
      config.anonKey,
      session,
      ctx,
      data.fixture
    )
  } catch (error) {
    if (error && error.message && error.message.indexOf("auth HTTP 401") !== -1) {
      sleep(4)
      return
    }
    throw error
  }
}

function readConfig() {
  if (__ENV.LOADTEST_ENV !== "production") {
    throw new Error("Refusing to start: set LOADTEST_ENV=production.")
  }
  if (__ENV.TRADETRAXS_PROD_PERF_CONFIRM !== "yes") {
    throw new Error("Refusing to start: set TRADETRAXS_PROD_PERF_CONFIRM=yes.")
  }
  if (__ENV.TRADETRAXS_PROD_PERF_REALISTIC300_FULL !== "yes") {
    throw new Error(
      "Refusing realistic300_full: set TRADETRAXS_PROD_PERF_REALISTIC300_FULL=yes after reviewing docs."
    )
  }

  const maxVus = Number(__ENV.LOADTEST_MAX_VUS || 0)
  if (maxVus !== MAX_VUS) {
    throw new Error("LOADTEST_MAX_VUS must be " + MAX_VUS + " for realistic300_full.")
  }

  const supabaseUrl = requiredHttpsUrl("LOADTEST_SUPABASE_URL")
  const webUrl = requiredHttpsUrl("LOADTEST_WEB_URL")
  const anonKey = requiredEnv("LOADTEST_SUPABASE_ANON_KEY")
  assertProductionOnly(supabaseUrl, webUrl)

  if (anonKey.indexOf(SERVICE_ROLE_FRAGMENT) !== -1 || anonKey.indexOf("service_role") !== -1) {
    throw new Error("Refusing service-role credential.")
  }

  const users = JSON.parse(requiredEnv("LOADTEST_USERS_JSON"))
  if (!Array.isArray(users) || users.length !== 50) {
    throw new Error("realistic300_full requires exactly 50 users in LOADTEST_USERS_JSON.")
  }
  for (let i = 0; i < users.length; i++) {
    if (!users[i] || !users[i].email || !users[i].password) {
      throw new Error("Each load-test user needs email and password.")
    }
  }

  const feedScopeRaw = String(__ENV.LOADTEST_FEED_SCOPE || "following").trim().toLowerCase()
  if (feedScopeRaw !== "following" && feedScopeRaw !== "global") {
    throw new Error("LOADTEST_FEED_SCOPE must be following or global.")
  }

  let vuStartJitterSec = Number(__ENV.LOADTEST_VU_START_JITTER_SEC)
  if (!Number.isFinite(vuStartJitterSec) || vuStartJitterSec < 0) {
    vuStartJitterSec = 45
  }

  if (__ENV.LOADTEST_FULL_SKIP_PUSH !== "no") {
    if (__ENV.LOADTEST_FULL_SKIP_PUSH && __ENV.LOADTEST_FULL_SKIP_PUSH !== "yes") {
      throw new Error("LOADTEST_FULL_SKIP_PUSH must be yes (default) or no.")
    }
  }

  const sendCaps = parseGlobalSendCaps(__ENV)

  return {
    supabaseUrl: supabaseUrl,
    webUrl: webUrl,
    anonKey: anonKey,
    users: users,
    feedScope: feedScopeRaw,
    vuStartJitterSec: vuStartJitterSec,
    sendCaps: sendCaps,
  }
}

function assertProductionOnly(supabaseUrl, webUrl) {
  if (supabaseUrl.indexOf(STAGING_PROJECT_REF) !== -1) {
    throw new Error("Refusing staging Supabase URL.")
  }
  if (supabaseUrl.indexOf(PRODUCTION_PROJECT_REF) === -1) {
    throw new Error("LOADTEST_SUPABASE_URL must contain production project ref.")
  }
  const webHost = parseHttpsUrl(webUrl).hostname
  if (!ALLOWED_WEB_HOSTS[webHost]) {
    throw new Error("LOADTEST_WEB_URL must be tradetraxs.com production app host.")
  }
}

export function handleSummary(data) {
  const lines = [
    "TradeTraxs realistic300_full summary",
    "mode: realistic300_full  VUs: 300  duration: ~14m (3m ramp + 10m sustain + 1m down)",
    "sessions: up to 300 concurrent VUs on 50 authenticated accounts (pseudo-random VU→user map)",
    "300 concurrent virtual sessions ≠ 300 unique users",
    "fixture: LOADTEST_REALISTIC300_FULL_FIXTURE_JSON (isolated DM/room IDs only)",
    "push_notify: " + (__ENV.LOADTEST_FULL_SKIP_PUSH === "no" ? "ENABLED (avoid in prod)" : "disabled (LOADTEST_FULL_SKIP_PUSH=yes)"),
    "",
    "Workload: realistic150 read mix (85%) + DM/room/Realtime/notifications (15%)",
    "Writes: tagged [loadtest:realistic300_full] only; global caps " +
      (__ENV.LOADTEST_FULL_MAX_DM_SENDS_TOTAL || "200") +
      " DM / " +
      (__ENV.LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL || "200") +
      " room (partitioned across VUs, race-free)",
    "",
  ]
  appendRunTimingBreakdown(lines, data, { duration: "14m", vus: 300 })
  appendHttpAggregate(lines, data.metrics, "")
  appendEndpointLatency(lines, data.metrics, "")
  appendFeedCursorLatency(lines, data.metrics, "")
  appendHttpOutcomeCounters(lines, data.metrics, "")
  appendOkDurationByPage(lines, data.metrics, "")
  appendThresholdResults(lines, data.metrics)
  lines.push("")
  appendRealistic300FullMetrics(lines, data.metrics)
  lines.push("")
  lines.push(
    "note: interrupted iterations during graceful ramp-down appear in k6 progress line, not as a separate metric"
  )
  lines.push(
    "HTTP timeout: " +
      REQUEST_TIMEOUT +
      "; abort: fail rate ≥2%; global p95 ≥8s; feed/feed_page/dashboard_rpc p95 ≥5s"
  )
  lines.push("Cleanup: loadtest/scripts/cleanup-realistic300-full-data.mjs (after run)")
  lines.push("Audit: loadtest/docs/IOS_MESSAGING_REALTIME_AUDIT.md")
  lines.push("metrics JSON: loadtest/out/realistic300-full-last-summary.json (this run)")

  const snapshot = {
    mode: "realistic300_full",
    generatedAt: new Date().toISOString(),
    wallMs: data.state && data.state.testRunDuration,
    http: data.metrics && {
      http_req_failed_rate: data.metrics.http_req_failed && data.metrics.http_req_failed.values.rate,
      http_req_duration: data.metrics.http_req_duration && data.metrics.http_req_duration.values,
      iterations: data.metrics.iterations && data.metrics.iterations.values.count,
    },
    realistic300Full: snapshotRealistic300FullMetrics(data.metrics),
  }

  return {
    stdout: lines.join("\n") + "\n",
    "loadtest/out/realistic300-full-last-summary.json": JSON.stringify(snapshot, null, 2) + "\n",
  }
}
