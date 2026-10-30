/**
 * Client-realistic production read mix (still PostgREST — no Next.js server hop for Feed).
 */

import exec from "k6/execution"
import {
  scenarioCalendar,
  scenarioDashboard,
  scenarioDashboardRpc,
  scenarioFeedWithOptions,
  scenarioProfile,
  scenarioTrades,
} from "./read-workload-prod.js"

/** Weighted mix — Dashboard, Feed, Trades, Calendar, Profile (+ dashboard RPC occasionally). */
const MIX_BUCKETS = [
  { weight: 22, run: runDashboardBundle },
  { weight: 26, run: runFeedRealistic },
  { weight: 18, run: runTradesOnly },
  { weight: 14, run: runCalendarOnly },
  { weight: 12, run: runProfileOnly },
  { weight: 8, run: runDashboardRpcOnly },
]

function mixIndex(vuId, iteration) {
  const total = MIX_BUCKETS.reduce(function (sum, b) {
    return sum + b.weight
  }, 0)
  const slot = (vuId * 17 + iteration * 13) % total
  let cursor = 0
  for (let i = 0; i < MIX_BUCKETS.length; i++) {
    cursor += MIX_BUCKETS[i].weight
    if (slot < cursor) {
      return i
    }
  }
  return 0
}

function runDashboardBundle(base, anonKey, session, ctx) {
  scenarioDashboard(base, anonKey, session, ctx.paceShort)
  ctx.pace()
}

function runFeedRealistic(base, anonKey, session, ctx) {
  const paginate = exec.vu.iterationInScenario % 4 === 0
  scenarioFeedWithOptions(base, anonKey, session, {
    scope: ctx.feedScope,
    withPagination: paginate,
  })
  ctx.pace()
}

function runTradesOnly(base, anonKey, session, ctx) {
  scenarioTrades(base, anonKey, session)
  ctx.pace()
}

function runCalendarOnly(base, anonKey, session, ctx) {
  scenarioCalendar(base, anonKey, session)
  ctx.pace()
}

function runProfileOnly(base, anonKey, session, ctx) {
  scenarioProfile(base, anonKey, session)
  ctx.pace()
}

function runDashboardRpcOnly(base, anonKey, session, ctx) {
  scenarioDashboardRpc(base, anonKey, session)
  ctx.pace()
}

export function runClientRealisticIteration(base, anonKey, session, ctx) {
  const idx = mixIndex(exec.vu.idInTest, exec.vu.iterationInScenario)
  MIX_BUCKETS[idx].run(base, anonKey, session, ctx)
}
