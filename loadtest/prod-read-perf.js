/**
 * Production read-only performance probe (TradeTraxs).
 *
 * Modes (LOADTEST_PROD_PERF_MODE):
 *   smoke — 1 VU × 30s (run first)
 *   full  — 5 VU × 60s (requires TRADETRAXS_PROD_PERF_FULL=yes)
 *   ten   — 10 VU × 60s (requires TRADETRAXS_PROD_PERF_TEN=yes)
 *   twentyfive — 25 VU × 60s (requires TRADETRAXS_PROD_PERF_TWENTYFIVE=yes)
 *   fifty — 50 VU × 60s (requires TRADETRAXS_PROD_PERF_FIFTY=yes)
 *   seventyfive — 75 VU × 60s (requires TRADETRAXS_PROD_PERF_SEVENTYFIVE=yes)
 *   hundred — 100 VU × 60s (requires TRADETRAXS_PROD_PERF_HUNDRED=yes)
 *   onefifty — 150 VU × 60s (requires TRADETRAXS_PROD_PERF_ONEFIFTY=yes)
 *   realistic150 — ramp to 150 VU, sustained iOS-shaped mix (requires TRADETRAXS_PROD_PERF_REALISTIC150=yes)
 *   realistic300 — ramp to 300 VU, same iOS-shaped mix (requires TRADETRAXS_PROD_PERF_REALISTIC300=yes)
 *
 * Gates: LOADTEST_ENV=production, TRADETRAXS_PROD_PERF_CONFIRM=yes
 *
 * Workloads (LOADTEST_WORKLOAD_KIND): see loadtest/WORKLOAD_TAXONOMY.md
 *   supabase_direct   — PostgREST stress (default)
 *   client_realistic — app-shaped mix + jitter (still PostgREST; no browser cache)
 *
 * API contracts: loadtest/lib/read-workload-prod.js (shared with preflight).
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
} from "./lib/k6-summary.js"
import { runClientRealisticIteration } from "./lib/read-workload-realistic.js"
import { runRealistic150Iteration } from "./lib/read-workload-realistic150.js"
import { formatSetupAuthFailure } from "./lib/auth-grant-diagnostics.js"
import {
  loginPasswordGrant,
  loginPasswordGrantDetailed,
  runProductionReadPreflight,
  runSupabaseDirectIteration,
} from "./lib/read-workload-prod.js"
import {
  parseWorkloadKind,
  WORKLOAD_CLIENT_REALISTIC,
  WORKLOAD_REALISTIC150,
  workloadSummaryLines,
} from "./lib/workload-kinds.js"
import { applyStageStartJitter } from "./lib/vu-jitter.js"

const SERVICE_ROLE_FRAGMENT = "c2VydmljZV9yb2xl"
const ALLOWED_WEB_HOSTS = {
  "tradetraxs.com": true,
  "www.tradetraxs.com": true,
  "app.tradetraxs.com": true,
}

const MIN_PACE_SEC = 4
const MAX_PACE_SEC = 8

const MODE_PROFILES = {
  smoke: {
    vus: 1,
    duration: "30s",
    maxVus: 1,
    maxUsers: 1,
    confirmEnv: null,
    executor: "constant-vus",
  },
  full: {
    vus: 5,
    duration: "60s",
    maxVus: 5,
    maxUsers: 5,
    confirmEnv: "TRADETRAXS_PROD_PERF_FULL",
    executor: "constant-vus",
  },
  ten: {
    vus: 10,
    duration: "60s",
    maxVus: 10,
    maxUsers: 10,
    confirmEnv: "TRADETRAXS_PROD_PERF_TEN",
    executor: "constant-vus",
  },
  twentyfive: {
    vus: 25,
    duration: "60s",
    maxVus: 25,
    maxUsers: 25,
    confirmEnv: "TRADETRAXS_PROD_PERF_TWENTYFIVE",
    executor: "constant-vus",
  },
  fifty: {
    vus: 50,
    duration: "60s",
    maxVus: 50,
    maxUsers: 50,
    confirmEnv: "TRADETRAXS_PROD_PERF_FIFTY",
    executor: "constant-vus",
  },
  seventyfive: {
    vus: 75,
    duration: "60s",
    maxVus: 75,
    maxUsers: 75,
    confirmEnv: "TRADETRAXS_PROD_PERF_SEVENTYFIVE",
    executor: "constant-vus",
  },
  hundred: {
    vus: 100,
    duration: "60s",
    maxVus: 100,
    maxUsers: 100,
    confirmEnv: "TRADETRAXS_PROD_PERF_HUNDRED",
    executor: "constant-vus",
  },
  onefifty: {
    vus: 150,
    duration: "60s",
    maxVus: 150,
    maxUsers: 150,
    minUsers: 50,
    confirmEnv: "TRADETRAXS_PROD_PERF_ONEFIFTY",
    executor: "constant-vus",
  },
  realistic150: {
    vus: 150,
    duration: "14m",
    maxVus: 150,
    maxUsers: 50,
    minUsers: 50,
    confirmEnv: "TRADETRAXS_PROD_PERF_REALISTIC150",
    executor: "ramping-vus",
    stages: [
      { duration: "3m", target: 150 },
      { duration: "10m", target: 150 },
      { duration: "1m", target: 0 },
    ],
  },
  realistic300: {
    vus: 300,
    duration: "14m",
    maxVus: 300,
    maxUsers: 50,
    minUsers: 50,
    confirmEnv: "TRADETRAXS_PROD_PERF_REALISTIC300",
    executor: "ramping-vus",
    stages: [
      { duration: "3m", target: 300 },
      { duration: "10m", target: 300 },
      { duration: "1m", target: 0 },
    ],
  },
}

function isRealisticIosRampMode(mode) {
  return mode === "realistic150" || mode === "realistic300"
}

const config = readConfig()

globalThis.__recordHttpOutcome = recordHttpOutcome

export const options = buildOptions(config)

function buildOptions(cfg) {
  const base = {
    discardResponseBodies: true,
    summaryTrendStats: ["avg", "p(50)", "p(95)", "p(99)", "count"],
    thresholds: {
      http_req_failed: [{ threshold: "rate<0.02", abortOnFail: true }],
      http_req_duration: [{ threshold: "p(95)<8000", abortOnFail: true }],
      "http_req_duration{page:dashboard_rpc}": [{ threshold: "p(95)<5000", abortOnFail: true }],
      /** Stricter than global 8s — feed RPC is the heaviest read path; evaluates all samples continuously. */
      "http_req_duration{page:feed}": [{ threshold: "p(95)<5000", abortOnFail: true }],
      "http_req_duration{page:feed_page}": [{ threshold: "p(95)<5000", abortOnFail: true }],
    },
  }

  if (cfg.profile.executor === "ramping-vus") {
    base.scenarios = {
      prod_read_only: {
        executor: "ramping-vus",
        startVUs: 0,
        stages: cfg.profile.stages,
        gracefulRampDown: "2m",
        tags: { workload: cfg.workloadKind },
      },
    }
  } else {
    base.scenarios = {
      prod_read_only: {
        executor: "constant-vus",
        vus: cfg.profile.vus,
        duration: cfg.profile.duration,
        gracefulStop: "10s",
        tags: { workload: cfg.workloadKind },
      },
    }
  }
  return base
}

const SETUP_AUTH_SPACING_SEC = 0.85

/** Wall time for k6 setup() (JWT grants + RPC preflight); excluded from VU HTTP metrics. */
const setupWallMs = new Trend("tradetraxs_setup_wall_ms", true)

export function setup() {
  const setupStarted = Date.now()
  const sessionsByEmail = {}
  for (let i = 0; i < config.users.length; i++) {
    if (i > 0) {
      sleep(SETUP_AUTH_SPACING_SEC)
    }
    const user = config.users[i]
    const grant = loginPasswordGrantDetailed(
      config.supabaseUrl,
      config.anonKey,
      user,
      "setup_auth"
    )
    if (!grant.session) {
      throw new Error(formatSetupAuthFailure(i, user.email, grant.failure))
    }
    const session = grant.session
    sessionsByEmail[user.email] = {
      email: session.email,
      userId: session.userId,
      token: session.token,
    }
  }

  const preflightSession = sessionsByEmail[config.users[0].email]
  runProductionReadPreflight(config.supabaseUrl, config.anonKey, preflightSession)
  assertPacingConfigured()
  setupWallMs.add(Date.now() - setupStarted)
  const payload = { preflight: "ok", mode: config.mode, sessionsByEmail: sessionsByEmail }
  if (isRealisticIosRampMode(config.mode)) {
    payload.vuUserIndex = buildVuUserIndex(config.profile.maxVus, config.users.length)
  }
  return payload
}

/** Stable pseudo-random mapping: N VUs → 50 accounts (~N/50 sessions per account on average). */
function buildVuUserIndex(maxVus, userCount) {
  const indices = []
  for (let vu = 1; vu <= maxVus; vu++) {
    indices.push((vu * 48271 + 104729) % userCount)
  }
  return indices
}

/** Per-VU session cache (setup tokens; throttled refresh only on 401 / missing seed). */
let vuSession = null
let vuSessionEmail = null
let vuAuthRefreshNotBefore = 0
let activeScenario = null

const AUTH_REFRESH_COOLDOWN_MS = 30000

function cloneSessionFromSetup(seed) {
  return {
    email: seed.email,
    userId: seed.userId,
    token: seed.token,
  }
}

function refreshSessionThrottled(user) {
  const now = Date.now()
  if (now < vuAuthRefreshNotBefore) {
    return null
  }
  sleep(Math.random() * 2)
  vuAuthRefreshNotBefore = now + AUTH_REFRESH_COOLDOWN_MS + Math.floor(Math.random() * 5000)
  const refreshed = loginPasswordGrant(
    config.supabaseUrl,
    config.anonKey,
    user,
    "auth_refresh"
  )
  if (refreshed) {
    vuSession = refreshed
    vuSessionEmail = user.email
  }
  return refreshed
}

function resolveUserForVu(data, vuId) {
  if (isRealisticIosRampMode(config.mode) && data.vuUserIndex && data.vuUserIndex.length >= vuId) {
    return config.users[data.vuUserIndex[vuId - 1]]
  }
  return config.users[(vuId - 1) % config.users.length]
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

function isAuthHttpError(error) {
  return (
    error &&
    error.message &&
    (error.message.indexOf("auth HTTP 401") !== -1 ||
      error.message.indexOf("(auth HTTP 401)") !== -1)
  )
}

function runIterationForSession(base, anonKey, session, ctx) {
  if (config.workloadKind === WORKLOAD_REALISTIC150) {
    runRealistic150Iteration(base, anonKey, session, ctx)
  } else if (config.workloadKind === WORKLOAD_CLIENT_REALISTIC) {
    runClientRealisticIteration(base, anonKey, session, ctx)
  } else {
    runSupabaseDirectIteration(base, anonKey, session, ctx)
  }
}

export default function (data) {
  const scen = exec.scenario.name
  if (scen !== activeScenario) {
    activeScenario = scen
    const stageVus = config.stageVusByScenario[scen] || config.profile.maxVus
    applyStageStartJitter(exec.vu.idInTest, stageVus, config.vuStartJitterSec)
  }

  const user = resolveUserForVu(data, exec.vu.idInTest)
  let session = resolveSession(data, user)
  if (!session) {
    sleep(MIN_PACE_SEC)
    return
  }

  const base = config.supabaseUrl
  const anonKey = config.anonKey
  const ctx = {
    pace: pace,
    paceShort: paceShort,
    feedScope: config.feedScope,
  }

  try {
    runIterationForSession(base, anonKey, session, ctx)
  } catch (error) {
    if (!isAuthHttpError(error)) {
      throw error
    }
    const refreshed = refreshSessionThrottled(user)
    if (!refreshed) {
      sleep(MIN_PACE_SEC)
      return
    }
    session = refreshed
    try {
      runIterationForSession(base, anonKey, session, ctx)
    } catch (retryError) {
      if (isAuthHttpError(retryError)) {
        sleep(MIN_PACE_SEC)
        return
      }
      throw retryError
    }
  }
}

function readConfig() {
  if (__ENV.LOADTEST_ENV !== "production") {
    throw new Error("Refusing to start: set LOADTEST_ENV=production for this script only.")
  }
  if (__ENV.TRADETRAXS_PROD_PERF_CONFIRM !== "yes") {
    throw new Error(
      "Refusing to start: set TRADETRAXS_PROD_PERF_CONFIRM=yes after reviewing loadtest/PRODUCTION_READ_PERF.md"
    )
  }

  const mode = String(__ENV.LOADTEST_PROD_PERF_MODE || "smoke").trim().toLowerCase()
  const profile = MODE_PROFILES[mode]
  if (!profile) {
    throw new Error(
      "LOADTEST_PROD_PERF_MODE must be smoke, full, ten, twentyfive, fifty, seventyfive, hundred, onefifty, realistic150, or realistic300."
    )
  }
  if (profile.confirmEnv && __ENV[profile.confirmEnv] !== "yes") {
    throw new Error(
      "Refusing " +
        mode +
        " run: set " +
        profile.confirmEnv +
        "=yes only after a successful smoke test."
    )
  }

  const supabaseUrl = requiredHttpsUrl("LOADTEST_SUPABASE_URL")
  const webUrl = requiredHttpsUrl("LOADTEST_WEB_URL")
  const anonKey = requiredEnv("LOADTEST_SUPABASE_ANON_KEY")
  assertProductionOnly(supabaseUrl, webUrl)
  assertProductionProjectRef(supabaseUrl)

  const maxVus = Number(__ENV.LOADTEST_MAX_VUS || 0)
  if (maxVus !== profile.maxVus) {
    throw new Error("LOADTEST_MAX_VUS must be " + profile.maxVus + " for mode " + mode + ".")
  }

  if (anonKey.indexOf(SERVICE_ROLE_FRAGMENT) !== -1 || anonKey.indexOf("service_role") !== -1) {
    throw new Error("Refusing service-role credential.")
  }

  const users = JSON.parse(requiredEnv("LOADTEST_USERS_JSON"))
  if (!Array.isArray(users) || users.length === 0 || users.length > profile.maxUsers) {
    throw new Error(
      "LOADTEST_USERS_JSON: 1–" + profile.maxUsers + " dedicated production test user(s)."
    )
  }
  if (profile.minUsers && users.length !== profile.minUsers) {
    throw new Error(
      mode +
        " requires exactly " +
        profile.minUsers +
        " dedicated users in LOADTEST_USERS_JSON (have " +
        users.length +
        ")."
    )
  }
  for (let i = 0; i < users.length; i++) {
    if (!users[i] || !users[i].email || !users[i].password) {
      throw new Error("Each load-test user needs email and password.")
    }
  }

  let workloadKind = parseWorkloadKind(__ENV.LOADTEST_WORKLOAD_KIND)
  if (isRealisticIosRampMode(mode)) {
    workloadKind = WORKLOAD_REALISTIC150
  }
  const feedScopeDefault =
    workloadKind === WORKLOAD_CLIENT_REALISTIC || workloadKind === WORKLOAD_REALISTIC150
      ? "following"
      : "global"
  const feedScopeRaw = String(__ENV.LOADTEST_FEED_SCOPE || feedScopeDefault)
    .trim()
    .toLowerCase()
  if (feedScopeRaw !== "following" && feedScopeRaw !== "global") {
    throw new Error("LOADTEST_FEED_SCOPE must be following or global.")
  }

  let vuStartJitterSec = Number(__ENV.LOADTEST_VU_START_JITTER_SEC)
  if (!Number.isFinite(vuStartJitterSec) || vuStartJitterSec < 0) {
    vuStartJitterSec =
      workloadKind === WORKLOAD_CLIENT_REALISTIC
        ? 12
        : workloadKind === WORKLOAD_REALISTIC150
          ? 45
          : 0
  }

  const stageVusByScenario = { prod_read_only: profile.maxVus }

  return {
    mode: mode,
    profile: profile,
    workloadKind: workloadKind,
    feedScope: feedScopeRaw,
    vuStartJitterSec: vuStartJitterSec,
    stageVusByScenario: stageVusByScenario,
    supabaseUrl: supabaseUrl,
    webUrl: webUrl,
    anonKey: anonKey,
    users: users,
  }
}

function assertPacingConfigured() {
  if (MIN_PACE_SEC < 4 || MAX_PACE_SEC > 8 || MIN_PACE_SEC >= MAX_PACE_SEC) {
    throw new Error("Preflight failed: pacing limits misconfigured")
  }
}

function assertProductionOnly(supabaseUrl, webUrl) {
  if (supabaseUrl.indexOf(STAGING_PROJECT_REF) !== -1) {
    throw new Error("Refusing staging Supabase URL in production perf test.")
  }
  if (supabaseUrl.indexOf(PRODUCTION_PROJECT_REF) === -1) {
    throw new Error("LOADTEST_SUPABASE_URL must contain production project ref " + PRODUCTION_PROJECT_REF)
  }
  const webHost = parseHttpsUrl(webUrl).hostname
  if (!ALLOWED_WEB_HOSTS[webHost]) {
    throw new Error("LOADTEST_WEB_URL must be tradetraxs.com production app host (got " + webHost + ")")
  }
}

function assertProductionProjectRef(supabaseUrl) {
  const expected = __ENV.TRADETRAXS_PRODUCTION_PROJECT_REF || PRODUCTION_PROJECT_REF
  if (String(expected).trim() !== PRODUCTION_PROJECT_REF) {
    throw new Error("TRADETRAXS_PRODUCTION_PROJECT_REF must be " + PRODUCTION_PROJECT_REF)
  }
  if (supabaseUrl.indexOf(PRODUCTION_PROJECT_REF) === -1) {
    throw new Error("Supabase URL must match TRADETRAXS_PRODUCTION_PROJECT_REF.")
  }
}

function pace() {
  sleep(MIN_PACE_SEC + Math.random() * (MAX_PACE_SEC - MIN_PACE_SEC))
}

function paceShort() {
  sleep(0.5 + Math.random() * 0.5)
}

export function handleSummary(data) {
  const lines = [
    "TradeTraxs production read-only perf summary",
    "mode: " + config.mode + "  VUs: " + config.profile.vus + "  duration: " + config.profile.duration,
    "feed_scope: " + config.feedScope + "  vu_start_jitter_sec: " + config.vuStartJitterSec,
    isRealisticIosRampMode(config.mode)
      ? "sessions: up to " +
        config.profile.maxVus +
        " concurrent VUs on " +
        config.users.length +
        " authenticated accounts (pseudo-random VU→user map; " +
        config.profile.maxVus +
        " sessions ≠ " +
        config.profile.maxVus +
        " unique users)"
      : "test_users: " + config.users.length + " (VUs round-robin by vu.idInTest)",
    "",
  ]
  const workloadLines = workloadSummaryLines(config.workloadKind)
  for (let i = 0; i < workloadLines.length; i++) {
    lines.push(workloadLines[i])
  }
  lines.push("")
  appendRunTimingBreakdown(lines, data, config.profile)

  appendHttpAggregate(lines, data.metrics, "")
  appendEndpointLatency(lines, data.metrics, "")
  appendFeedCursorLatency(lines, data.metrics, "")
  appendHttpOutcomeCounters(lines, data.metrics, "")
  appendOkDurationByPage(lines, data.metrics, "")
  appendThresholdResults(lines, data.metrics)
  lines.push("")
  lines.push(
    "Note: HTTP 0 / client_timeout = k6 hit REQUEST_TIMEOUT (" +
      REQUEST_TIMEOUT +
      "); feed p95≈8001ms usually means timeouts in the feed sample, not slow 200 responses."
  )
  lines.push("")
  if (config.workloadKind === WORKLOAD_REALISTIC150) {
    lines.push(
      "Pacing: iOS-realistic150 — 10–60s between active fetches; 60–180s idle; screen TTL cache skips redundant reads."
    )
    lines.push(
      "Excluded: writes, messaging, Realtime, media/CDN downloads (see loadtest/docs/PROD_PERF_REALISTIC150.md and PROD_PERF_REALISTIC300.md)."
    )
  } else {
    lines.push("Pacing enforced: " + MIN_PACE_SEC + "–" + MAX_PACE_SEC + "s between page groups per VU.")
  }
  lines.push(
    "Auto-stop: failed rate ≥2%; global p95 ≥8s; feed/feed_page/dashboard_rpc p95 ≥5s (abortOnFail, continuous eval)."
  )
  lines.push("Emergency stop: Ctrl+C once = graceful wind-down; Ctrl+C twice = immediate abort. Watch Supabase/Vercel.")
  lines.push("Record Supabase (CPU, connections, API 5xx) and Vercel errors manually during the run.")
  if (config.mode === "smoke") {
    lines.push("After smoke: ten-VU — LOADTEST_PROD_PERF_MODE=ten, LOADTEST_MAX_VUS=10, TRADETRAXS_PROD_PERF_TEN=yes")
  }
  return {
    stdout: lines.join("\n") + "\n",
  }
}
