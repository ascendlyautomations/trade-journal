/**
 * Phase A read-only load test for TradeTraxs staging.
 *
 * Refuses production. API contracts: loadtest/lib/read-workload-*.js
 */
import { sleep } from "k6"
import exec from "k6/execution"
import { PRODUCTION_PROJECT_REF, STAGING_PROJECT_REF } from "./lib/constants.js"
import { parseHttpsUrl, requiredEnv, requiredHttpsUrl } from "./lib/k6-shared.js"
import {
  loginPasswordGrant,
  runStagingReadPreflight,
  scenarioDashboard,
  scenarioFeed,
  scenarioLeaderboard,
  scenarioMessages,
  scenarioProfile,
  scenarioTrades,
} from "./lib/read-workload-staging.js"

const PRODUCTION_HOSTS = {
  "tradetraxs.com": true,
  "www.tradetraxs.com": true,
  "app.tradetraxs.com": true,
}
const SERVICE_ROLE_FRAGMENT = "c2VydmljZV9yb2xl"
const ALLOWED_VUS = { 1: true, 10: true, 25: true, 50: true, 100: true }

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

export function setup() {
  const user = config.users[0]
  const session = loginPasswordGrant(config.supabaseUrl, config.anonKey, user, "preflight_auth")
  if (!session) {
    throw new Error("Preflight failed: authentication")
  }
  runStagingReadPreflight(config.supabaseUrl, config.anonKey, session)
  return { preflight: "ok" }
}

let session = null

export default function () {
  const user = config.users[(exec.vu.idInTest - 1) % config.users.length]
  if (!session || session.email !== user.email) {
    session = loginPasswordGrant(config.supabaseUrl, config.anonKey, user, "auth")
  }
  if (!session) {
    sleep(5)
    return
  }

  const base = config.supabaseUrl
  const anonKey = config.anonKey
  const route = exec.vu.idInTest % 5
  if (route === 0) {
    scenarioDashboard(base, anonKey, session, thinkShort)
    think()
    scenarioFeed(base, anonKey, session, false)
    think()
    scenarioProfile(base, anonKey, session)
    think()
    scenarioTrades(base, anonKey, session)
  } else if (route === 1) {
    scenarioFeed(base, anonKey, session, true)
    think()
    scenarioProfile(base, anonKey, session)
  } else if (route === 2) {
    scenarioDashboard(base, anonKey, session, thinkShort)
    think()
    scenarioTrades(base, anonKey, session)
  } else if (route === 3) {
    scenarioMessages(base, anonKey, session)
  } else {
    scenarioDashboard(base, anonKey, session, thinkShort)
    think()
    scenarioLeaderboard(config.webUrl, session)
  }
  think()
}

function readConfig() {
  if (__ENV.LOADTEST_ENV !== "staging") {
    throw new Error("Refusing to start: set LOADTEST_ENV=staging. Production is blocked.")
  }

  const supabaseUrl = requiredHttpsUrl("LOADTEST_SUPABASE_URL")
  const webUrl = requiredHttpsUrl("LOADTEST_WEB_URL")
  const anonKey = requiredEnv("LOADTEST_SUPABASE_ANON_KEY")
  assertNotProduction(supabaseUrl)
  assertNotProduction(webUrl)
  assertStagingProjectRef(supabaseUrl)
  if (anonKey.indexOf(SERVICE_ROLE_FRAGMENT) !== -1 || anonKey.indexOf("service_role") !== -1) {
    throw new Error("Refusing service-role credential.")
  }

  const maxVus = Number(__ENV.LOADTEST_MAX_VUS || 10)
  if (!ALLOWED_VUS[maxVus]) {
    throw new Error("LOADTEST_MAX_VUS must be 1, 10, 25, 50, or 100.")
  }

  const users = JSON.parse(requiredEnv("LOADTEST_USERS_JSON"))
  if (!Array.isArray(users) || users.length === 0) {
    throw new Error("LOADTEST_USERS_JSON must be a non-empty JSON array.")
  }
  for (let i = 0; i < users.length; i++) {
    if (!users[i] || !users[i].email || !users[i].password) {
      throw new Error("Each load-test user needs email and password.")
    }
  }

  return {
    supabaseUrl: supabaseUrl,
    webUrl: webUrl,
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

function assertNotProduction(rawUrl) {
  const parsed = parseHttpsUrl(rawUrl)
  if (!parsed) {
    throw new Error("URL is not https")
  }
  const host = parsed.hostname
  if (PRODUCTION_HOSTS[host] || rawUrl.indexOf(PRODUCTION_PROJECT_REF) !== -1) {
    throw new Error("Refusing production URL: " + host)
  }
}

function assertStagingProjectRef(supabaseUrl) {
  const expected = __ENV.TRADETRAXS_STAGING_PROJECT_REF
  if (!expected || !String(expected).trim()) {
    throw new Error(
      "Refusing to start: set TRADETRAXS_STAGING_PROJECT_REF to your staging Supabase project ref."
    )
  }
  const ref = String(expected).trim()
  if (ref === PRODUCTION_PROJECT_REF) {
    throw new Error("TRADETRAXS_STAGING_PROJECT_REF must not be the production project ref.")
  }
  if (ref !== STAGING_PROJECT_REF) {
    throw new Error(
      "TRADETRAXS_STAGING_PROJECT_REF must be " + STAGING_PROJECT_REF + " (got " + ref + ")."
    )
  }
  if (supabaseUrl.indexOf(ref) === -1) {
    throw new Error(
      "LOADTEST_SUPABASE_URL must contain TRADETRAXS_STAGING_PROJECT_REF (" + ref + ")."
    )
  }
}

function think() {
  sleep(3 + Math.random() * 5)
}

function thinkShort() {
  sleep(0.4 + Math.random() * 0.6)
}
