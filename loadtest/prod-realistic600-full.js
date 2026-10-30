/**
 * Production realistic600_full — same workload as realistic300_full at 600 VUs (overload probe).
 *
 * Separate from loadtest/prod-realistic300-full.js (300 VU SLO run unchanged).
 *
 * Gates:
 *   LOADTEST_ENV=production
 *   TRADETRAXS_PROD_PERF_CONFIRM=yes
 *   TRADETRAXS_PROD_PERF_REALISTIC600_FULL=yes
 *   LOADTEST_MAX_VUS=600
 *   LOADTEST_REALISTIC600_FULL_FIXTURE_JSON — 100-account isolation fixture
 *   LOADTEST_REALISTIC600_USERS_JSON — 100 perf JWTs (LOADTEST_USERS_JSON stays 50 for 300_full)
 *   LOADTEST_FULL_MESSAGE_TAG=[loadtest:realistic600_full]
 *   LOADTEST_FULL_MAX_DM_SENDS_TOTAL=400, LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL=400 (800 sends total)
 *   LOADTEST_K6_SETUP_AUTH_SPACING_SEC — seconds between setup password grants (default 3 for 100 accounts)
 *
 * Do not run without reviewing loadtest/docs/PROD_PERF_REALISTIC600_FULL.md
 *
 * VU workload: runRealistic300FullIteration (85% read / 15% messaging+Realtime weights in read-workload-realistic300-full.js).
 * Launch: loadtest/scripts/run-realistic600-full.sh (mkdir loadtest/out + fixture export).
 */
import { sleep } from "k6"
import exec from "k6/execution"
import { Trend } from "k6/metrics"
import { recordHttpOutcome } from "./lib/k6-diagnostics.js"
import { PRODUCTION_PROJECT_REF, REQUEST_TIMEOUT, STAGING_PROJECT_REF } from "./lib/constants.js"
import { parseHttpsUrl, requiredEnv, requiredHttpsUrl } from "./lib/k6-shared.js"
import { buildRealisticFullSummaryOutput } from "./lib/k6-summary.js"
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

const MAX_VUS = 600
const REQUIRED_USER_COUNT = 100
const VUS_PER_USER = MAX_VUS / REQUIRED_USER_COUNT
/** Global cluster caps (partitioned across all VUs — not per-VU totals). */
const REQUIRED_DM_SENDS_TOTAL = 400
const REQUIRED_ROOM_SENDS_TOTAL = 400
/** Default spacing for 100 setup grants (~5 min) — override with LOADTEST_K6_SETUP_AUTH_SPACING_SEC. */
const DEFAULT_SETUP_AUTH_SPACING_SEC = 3
const setupWallMs = new Trend("tradetraxs_setup_wall_ms", true)

const config = readConfig()

globalThis.__recordHttpOutcome = recordHttpOutcome

export const options = {
  discardResponseBodies: true,
  /** 100 grants @ default 3s spacing + 429 retries + RPC preflight (first user token only). */
  setupTimeout: "12m",
  summaryTrendStats: ["avg", "p(50)", "p(95)", "p(99)", "count"],
  scenarios: {
    realistic600_full: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "5m", target: MAX_VUS },
        { duration: "10m", target: MAX_VUS },
        { duration: "2m", target: 0 },
      ],
      gracefulRampDown: "2m",
      tags: { workload: "realistic600_full_ios" },
    },
  },
  thresholds: {
    http_req_failed: [{ threshold: "rate<0.99", abortOnFail: false }],
    http_req_duration: [{ threshold: "p(95)<120000", abortOnFail: false }],
    "http_req_duration{page:dashboard_rpc}": [{ threshold: "p(95)<120000", abortOnFail: false }],
    "http_req_duration{page:feed}": [{ threshold: "p(95)<120000", abortOnFail: false }],
    "http_req_duration{page:feed_page}": [{ threshold: "p(95)<120000", abortOnFail: false }],
  },
}

export function setup() {
  const setupStarted = Date.now()
  const fixture = parseRealistic300FullFixture(requiredEnv("LOADTEST_REALISTIC600_FULL_FIXTURE_JSON"))
  const fixtureEmailSet = fixtureEmailsLower(fixture)

  const sessionsByEmail = {}
  for (let i = 0; i < config.users.length; i++) {
    if (i > 0) {
      sleep(config.setupAuthSpacingSec)
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
    mode: "realistic600_full",
    fixtureTag: fixture.tag,
    fixture: fixture,
    sessionsByEmail: sessionsByEmail,
    vuUserIndex: buildVuUserIndexEven(MAX_VUS, config.users.length),
  }
}

/** Exactly maxVus / userCount sessions per account (600 VUs → 6 each on 100 accounts). */
function buildVuUserIndexEven(maxVus, userCount) {
  if (maxVus % userCount !== 0) {
    throw new Error("maxVus must be divisible by userCount for even VU distribution")
  }
  const perUser = maxVus / userCount
  const indices = []
  for (let u = 0; u < userCount; u++) {
    for (let k = 0; k < perUser; k++) {
      indices.push(u)
    }
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
  if (__ENV.TRADETRAXS_PROD_PERF_REALISTIC600_FULL !== "yes") {
    throw new Error(
      "Refusing realistic600_full: set TRADETRAXS_PROD_PERF_REALISTIC600_FULL=yes after reviewing docs."
    )
  }
  if (__ENV.TRADETRAXS_PROD_PERF_REALISTIC1000_FULL === "yes") {
    throw new Error(
      "Refusing realistic600_full: unset TRADETRAXS_PROD_PERF_REALISTIC1000_FULL (only one full probe gate at a time)."
    )
  }

  const maxVus = Number(__ENV.LOADTEST_MAX_VUS || 0)
  if (maxVus !== MAX_VUS) {
    throw new Error("LOADTEST_MAX_VUS must be " + MAX_VUS + " for realistic600_full.")
  }

  const supabaseUrl = requiredHttpsUrl("LOADTEST_SUPABASE_URL")
  const webUrl = requiredHttpsUrl("LOADTEST_WEB_URL")
  const anonKey = requiredEnv("LOADTEST_SUPABASE_ANON_KEY")
  assertProductionOnly(supabaseUrl, webUrl)

  if (anonKey.indexOf(SERVICE_ROLE_FRAGMENT) !== -1 || anonKey.indexOf("service_role") !== -1) {
    throw new Error("Refusing service-role credential.")
  }

  const users = JSON.parse(requiredEnv("LOADTEST_REALISTIC600_USERS_JSON"))
  if (!Array.isArray(users) || users.length !== REQUIRED_USER_COUNT) {
    throw new Error(
      "realistic600_full requires exactly " +
        REQUIRED_USER_COUNT +
        " users in LOADTEST_REALISTIC600_USERS_JSON."
    )
  }
  const tagFromEnv = String(__ENV.LOADTEST_FULL_MESSAGE_TAG || "").trim()
  if (tagFromEnv !== "[loadtest:realistic600_full]") {
    throw new Error(
      'realistic600_full requires LOADTEST_FULL_MESSAGE_TAG="[loadtest:realistic600_full]" for cleanup isolation.'
    )
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
    vuStartJitterSec = 60
  }

  if (__ENV.LOADTEST_FULL_SKIP_PUSH !== "no") {
    if (__ENV.LOADTEST_FULL_SKIP_PUSH && __ENV.LOADTEST_FULL_SKIP_PUSH !== "yes") {
      throw new Error("LOADTEST_FULL_SKIP_PUSH must be yes (default) or no.")
    }
  }

  const sendCaps = parseGlobalSendCaps(__ENV)
  const dmTotal = sendCaps.dmTotal
  const roomTotal = sendCaps.roomTotal
  if (dmTotal !== REQUIRED_DM_SENDS_TOTAL || roomTotal !== REQUIRED_ROOM_SENDS_TOTAL) {
    throw new Error(
      "realistic600_full requires LOADTEST_FULL_MAX_DM_SENDS_TOTAL=" +
        REQUIRED_DM_SENDS_TOTAL +
        " and LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL=" +
        REQUIRED_ROOM_SENDS_TOTAL +
        " (global caps partitioned across " +
        MAX_VUS +
        " VUs)."
    )
  }

  return {
    supabaseUrl: supabaseUrl,
    webUrl: webUrl,
    anonKey: anonKey,
    users: users,
    feedScope: feedScopeRaw,
    vuStartJitterSec: vuStartJitterSec,
    sendCaps: sendCaps,
    setupAuthSpacingSec: readSetupAuthSpacingSec(),
  }
}

function readSetupAuthSpacingSec() {
  const raw = __ENV.LOADTEST_K6_SETUP_AUTH_SPACING_SEC
  if (raw != null && String(raw).trim() !== "") {
    const n = Number(raw)
    if (Number.isFinite(n) && n >= 0) {
      return n
    }
    throw new Error("LOADTEST_K6_SETUP_AUTH_SPACING_SEC must be a non-negative number.")
  }
  return DEFAULT_SETUP_AUTH_SPACING_SEC
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
  return buildRealisticFullSummaryOutput(data, {
    title: "TradeTraxs realistic600_full summary",
    mode: "realistic600_full",
    messageTag: "[loadtest:realistic600_full]",
    maxVus: MAX_VUS,
    durationDesc: "~19m (5m ramp + 10m sustain + 2m down + graceful ramp-down)",
    plannedDuration: "17m",
    jsonReportPath: "loadtest/out/realistic600-full-last-summary.json",
    configuredDmCap: REQUIRED_DM_SENDS_TOTAL,
    configuredRoomCap: REQUIRED_ROOM_SENDS_TOTAL,
    userCount: REQUIRED_USER_COUNT,
    vuMappingDesc: VUS_PER_USER + " VUs per account (even split)",
    fixtureEnvKey: "LOADTEST_REALISTIC600_FULL_FIXTURE_JSON",
    observeOnlyThresholds: true,
    overloadNote:
      "Overload probe: thresholds are informational (abortOnFail=false). HTTP/WS/DM failures surface via metrics and thrown errors.",
    sloLine:
      "HTTP timeout: " +
      REQUEST_TIMEOUT +
      "; informational thresholds only — high error/latency is expected under 600 VUs",
  })
}
