/**
 * iOS-shaped production read mix for realistic150 and realistic300 modes.
 * PostgREST only — simulates on-device screen cache TTLs (no HTTP when cache would hit).
 */

import exec from "k6/execution"
import { sleep } from "k6"
import {
  scenarioCalendar,
  scenarioDashboard,
  scenarioDashboardRpc,
  scenarioFeedWithOptions,
  scenarioProfile,
  scenarioTrades,
} from "./read-workload-prod.js"

/** Activity mix (weights sum to 100). */
const ACTIVITIES = [
  { id: "feed", weight: 25 },
  { id: "dashboard", weight: 15 },
  { id: "profile_trades", weight: 15 },
  { id: "calendar", weight: 10 },
  { id: "passive_view", weight: 15 },
  { id: "idle", weight: 20 },
]

/** Per-screen cache TTL (seconds) — refresh only after expiry or explicit pull-to-refresh. */
const CACHE_TTL_SEC = {
  feed: { min: 90, max: 180 },
  dashboard: { min: 120, max: 240 },
  profile_trades: { min: 120, max: 300 },
  calendar: { min: 180, max: 420 },
}

const PULL_TO_REFRESH_CHANCE = 0.07
const FEED_PAGINATE_CHANCE = 0.2
const DASHBOARD_RPC_BUNDLE_CHANCE = 0.35

function activityTotalWeight() {
  let sum = 0
  for (let i = 0; i < ACTIVITIES.length; i++) {
    sum += ACTIVITIES[i].weight
  }
  return sum
}

function pickActivity(vuId, iteration) {
  const total = activityTotalWeight()
  const slot = (vuId * 31 + iteration * 47 + vuId * iteration) % total
  let cursor = 0
  for (let i = 0; i < ACTIVITIES.length; i++) {
    cursor += ACTIVITIES[i].weight
    if (slot < cursor) {
      return ACTIVITIES[i].id
    }
  }
  return ACTIVITIES[0].id
}

function vuState() {
  if (!globalThis.__realistic150VuState) {
    globalThis.__realistic150VuState = {}
  }
  const key = exec.vu.idInTest
  if (!globalThis.__realistic150VuState[key]) {
    globalThis.__realistic150VuState[key] = {
      cache: {},
      lastContentScreen: null,
    }
  }
  return globalThis.__realistic150VuState[key]
}

function ttlForScreen(screen) {
  const spec = CACHE_TTL_SEC[screen]
  if (!spec) {
    return 120
  }
  return spec.min + Math.random() * (spec.max - spec.min)
}

function cacheFresh(state, screen, nowMs) {
  const entry = state.cache[screen]
  if (!entry) {
    return false
  }
  return nowMs - entry.atMs < entry.ttlSec * 1000
}

function touchCache(state, screen, nowMs) {
  state.cache[screen] = {
    atMs: nowMs,
    ttlSec: ttlForScreen(screen),
  }
  if (screen === "feed" || screen === "profile_trades") {
    state.lastContentScreen = screen
  }
}

function thinkBetweenActivities() {
  sleep(10 + Math.random() * 50)
}

function thinkPassiveContent() {
  sleep(12 + Math.random() * 38)
}

function thinkIdleBackground() {
  sleep(60 + Math.random() * 120)
}

function shouldForceRefresh() {
  return Math.random() < PULL_TO_REFRESH_CHANCE
}

function runFeed(base, anonKey, session, ctx, state, nowMs) {
  const force = shouldForceRefresh()
  if (!force && cacheFresh(state, "feed", nowMs)) {
    thinkPassiveContent()
    return
  }
  const paginate = Math.random() < FEED_PAGINATE_CHANCE
  scenarioFeedWithOptions(base, anonKey, session, {
    scope: ctx.feedScope,
    withPagination: paginate,
  })
  touchCache(state, "feed", nowMs)
  thinkBetweenActivities()
}

function runDashboard(base, anonKey, session, ctx, state, nowMs) {
  const force = shouldForceRefresh()
  if (!force && cacheFresh(state, "dashboard", nowMs)) {
    thinkPassiveContent()
    return
  }
  scenarioDashboard(base, anonKey, session, ctx.paceShort)
  if (Math.random() < DASHBOARD_RPC_BUNDLE_CHANCE) {
    sleep(0.4 + Math.random() * 0.8)
    scenarioDashboardRpc(base, anonKey, session)
  }
  touchCache(state, "dashboard", nowMs)
  thinkBetweenActivities()
}

function runProfileTrades(base, anonKey, session, state, nowMs) {
  const force = shouldForceRefresh()
  if (!force && cacheFresh(state, "profile_trades", nowMs)) {
    thinkPassiveContent()
    return
  }
  scenarioProfile(base, anonKey, session)
  sleep(0.5 + Math.random() * 1.2)
  scenarioTrades(base, anonKey, session)
  touchCache(state, "profile_trades", nowMs)
  thinkBetweenActivities()
}

function runCalendar(base, anonKey, session, state, nowMs) {
  const force = shouldForceRefresh()
  if (!force && cacheFresh(state, "calendar", nowMs)) {
    thinkPassiveContent()
    return
  }
  scenarioCalendar(base, anonKey, session)
  touchCache(state, "calendar", nowMs)
  thinkBetweenActivities()
}

/** User is reading/watching already-loaded feed or profile content — no new API calls. */
function runPassiveView(state) {
  if (!state.lastContentScreen) {
    thinkPassiveContent()
    return
  }
  thinkPassiveContent()
}

function runIdle() {
  thinkIdleBackground()
}

export function runRealistic150Activity(activity, base, anonKey, session, ctx) {
  const state = vuState()
  const nowMs = Date.now()

  if (activity === "feed") {
    runFeed(base, anonKey, session, ctx, state, nowMs)
  } else if (activity === "dashboard") {
    runDashboard(base, anonKey, session, ctx, state, nowMs)
  } else if (activity === "profile_trades") {
    runProfileTrades(base, anonKey, session, state, nowMs)
  } else if (activity === "calendar") {
    runCalendar(base, anonKey, session, state, nowMs)
  } else if (activity === "passive_view") {
    runPassiveView(state)
  } else if (activity === "idle") {
    runIdle()
  }

  if (Math.random() < 0.12) {
    sleep(2 + Math.random() * 6)
  }
}

export function runRealistic150Iteration(base, anonKey, session, ctx) {
  const activity = pickActivity(exec.vu.idInTest, exec.vu.iterationInScenario)
  runRealistic150Activity(activity, base, anonKey, session, ctx)
}

export { pickActivity, vuState }
