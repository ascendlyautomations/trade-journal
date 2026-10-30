import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const root = process.cwd()

function read(rel: string) {
  return fs.readFileSync(path.join(root, rel), "utf8")
}

function normalizeSelect(s: string) {
  return s.replace(/\s/g, "")
}

const prodScript = read("loadtest/prod-read-perf.js")
const prodFullScript = read("loadtest/prod-realistic300-full.js")
const prod600FullScript = read("loadtest/prod-realistic600-full.js")
const prod1000FullScript = read("loadtest/prod-realistic1000-full.js")
const stagingScript = read("loadtest/phase-a-read.js")
const constants = read("loadtest/lib/constants.js")
const k6Shared = read("loadtest/lib/k6-shared.js")
const rpcContracts = read("loadtest/lib/rpc-contracts.js")
const validators = read("loadtest/lib/validators.js")
const workloadProd = read("loadtest/lib/read-workload-prod.js")
const workloadStaging = read("loadtest/lib/read-workload-staging.js")
const k6Summary = read("loadtest/lib/k6-summary.js")
const k6Diagnostics = read("loadtest/lib/k6-diagnostics.js")
const workloadKinds = read("loadtest/lib/workload-kinds.js")
const workloadRealistic = read("loadtest/lib/read-workload-realistic.js")
const messagingWorkloadProd = read("loadtest/lib/messaging-workload-prod.js")
const sendBudget = read("loadtest/lib/realistic300-full-send-budget.js")
const cleanupScript = read("loadtest/scripts/cleanup-realistic300-full-data.mjs")
const vuJitter = read("loadtest/lib/vu-jitter.js")
const verifyProdEnv = read("loadtest/scripts/verify-production-perf-env.sh")
const appDataCache = read("lib/appDataCache.ts")
const publicPrivacy = read("lib/publicAccountPrivacy.ts")
const dbTypes = read("lib/database.types.ts")
const backendVersioning = read("lib/backendV2/versioning.ts")

describe("loadtest infrastructure", () => {
  it("shares constants with app ACCOUNTS_SELECT and analytics owner-read boundary", () => {
    const appMatch = appDataCache.match(
      /export const ACCOUNTS_SELECT\s*=\s*\n?\s*"([^"]+)"/
    )
    assert.ok(appMatch, "ACCOUNTS_SELECT in appDataCache")
    const appNorm = normalizeSelect(appMatch![1])
    const loadNorm = normalizeSelect(
      constants.match(/export const ACCOUNTS_SELECT\s*=\s*\n?\s*"([^"]+)"/)![1]
    )
    assert.equal(loadNorm, appNorm)

    assert.match(appDataCache, /rpcTradesOwnerRows/)
    assert.doesNotMatch(workloadProd, /TRADES_JOURNAL_SELECT/)
    assert.doesNotMatch(workloadProd, /TRADES_ANALYTICS_SELECT/)
    assert.match(workloadProd, /RPC_NAMES\.tradesOwnerRows/)
  })

  it("uses Backend V2 RPC names and database.types argument shapes", () => {
    assert.match(backendVersioning, /dashboard:\s*"rpc_v1_dashboard_bootstrap"/)
    assert.match(backendVersioning, /calendar:\s*"rpc_v1_calendar_bootstrap"/)
    assert.match(backendVersioning, /feed:\s*"rpc_v1_feed_bootstrap"/)

    assert.match(dbTypes, /rpc_v1_dashboard_bootstrap:[\s\S]*p_account_id\?:\s*string[\s\S]*p_trade_limit\?:\s*number/)
    assert.match(dbTypes, /rpc_v1_calendar_bootstrap:[\s\S]*p_month:\s*number[\s\S]*p_year:\s*number/)
    assert.match(dbTypes, /rpc_v1_trades_owner_rows:[\s\S]*p_limit\?:\s*number/)

    assert.match(rpcContracts, /p_trade_limit/)
    assert.match(rpcContracts, /p_year/)
    assert.match(rpcContracts, /p_month/)
    assert.doesNotMatch(rpcContracts, /p_user_id/)
    assert.doesNotMatch(rpcContracts, /p_recent_limit/)
  })

  it("is k6/goja compatible and handles discardResponseBodies", () => {
    for (const file of [prodScript, stagingScript, k6Shared, workloadProd]) {
      assert.doesNotMatch(file, /new URL\(/, "must not use browser URL in " + file.slice(0, 40))
    }
    assert.match(k6Shared, /parseHttpsUrl/)
    assert.match(k6Shared, /responseType.*parseBody|parseBody/)
    assert.match(k6Shared, /classifyHttpFailure/)
    assert.match(workloadProd, /preflight_profile", true\)/)
    assert.match(prodScript, /discardResponseBodies:\s*true/)
  })

  it("validates bootstrap envelopes and distinguishes failure classes", () => {
    assert.match(validators, /assertDashboardBootstrap/)
    assert.match(validators, /assertFeedBootstrap/)
    assert.match(validators, /assertCalendarBootstrap/)
    assert.match(validators, /assertOwnerTradeRows/)
    assert.match(k6Shared, /PGRST202/)
  })

  it("aligns production preflight with VU workload definitions", () => {
    assert.match(prodScript, /runProductionReadPreflight/)
    assert.match(prodScript, /sessionsByEmail/)
    assert.match(prodScript, /setup_auth/)
    assert.match(prodScript, /resolveSession\(data, user\)/)
    assert.match(prodScript, /refreshSessionThrottled/)
    assert.match(prodScript, /AUTH_REFRESH_COOLDOWN_MS/)
    assert.doesNotMatch(
      prodScript,
      /export default function \(\) \{[\s\S]*loginPasswordGrant[\s\S]*runClientRealisticIteration/
    )
    assert.match(workloadProd, /export function runProductionReadPreflight/)
    assert.match(workloadProd, /export function scenarioDashboard/)
    assert.match(workloadProd, /export function scenarioCalendar/)
    assert.match(workloadProd, /readCalendarBootstrap/)
    assert.match(workloadProd, /preflight_calendar/)
    assert.doesNotMatch(workloadProd, /preflight_calendar[\s\S]*TRADES_ANALYTICS/)
  })

  it("keeps production safety gates and smoke limits", () => {
    assert.match(prodScript, /LOADTEST_ENV !== "production"/)
    assert.match(prodScript, /TRADETRAXS_PROD_PERF_CONFIRM/)
    assert.match(prodScript, /smoke:[\s\S]*vus: 1[\s\S]*duration: "30s"/)
    assert.match(prodScript, /ten: \{[\s\S]*vus: 10[\s\S]*duration: "60s"/)
    assert.match(prodScript, /TRADETRAXS_PROD_PERF_TEN/)
    assert.match(prodScript, /twentyfive: \{[\s\S]*vus: 25[\s\S]*duration: "60s"/)
    assert.match(prodScript, /TRADETRAXS_PROD_PERF_TWENTYFIVE/)
    assert.match(prodScript, /fifty: \{[\s\S]*vus: 50[\s\S]*duration: "60s"/)
    assert.match(prodScript, /TRADETRAXS_PROD_PERF_FIFTY/)
    assert.match(prodScript, /seventyfive:[\s\S]*vus: 75[\s\S]*duration: "60s"/)
    assert.match(prodScript, /TRADETRAXS_PROD_PERF_SEVENTYFIVE/)
    assert.match(prodScript, /hundred:[\s\S]*vus: 100[\s\S]*duration: "60s"/)
    assert.match(prodScript, /TRADETRAXS_PROD_PERF_HUNDRED/)
    assert.match(prodScript, /onefifty:[\s\S]*vus: 150[\s\S]*duration: "60s"/)
    assert.match(prodScript, /TRADETRAXS_PROD_PERF_ONEFIFTY/)
    assert.doesNotMatch(prodScript, /HUNDRED_STAGE_PLAN/)
    assert.match(prodScript, /appendEndpointLatency/)
    assert.match(prodScript, /http_req_duration\{page:feed_page\}/)
    assert.match(k6Summary, /export function appendEndpointLatency/)
    assert.match(k6Summary, /export function findScenarioGroup/)
    assert.match(k6Summary, /appendFeedCursorLatency/)
    assert.match(k6Diagnostics, /client_timeout/)
    assert.match(workloadProd, /feed_cursor/)
    assert.match(prodScript, /LOADTEST_WORKLOAD_KIND/)
    assert.match(prodScript, /runSupabaseDirectIteration/)
    assert.match(prodScript, /runClientRealisticIteration/)
    assert.match(prodScript, /applyStageStartJitter/)
    assert.match(workloadKinds, /WORKLOAD_SUPABASE_DIRECT/)
    assert.match(workloadKinds, /WORKLOAD_CLIENT_REALISTIC/)
    assert.match(workloadRealistic, /runClientRealisticIteration/)
    assert.match(vuJitter, /stageStartJitterSec/)
    assert.match(verifyProdEnv, /client_realistic requires >= 5 dedicated users/)
    assert.match(verifyProdEnv, /LOADTEST_MAX_VUS must be 50 for fifty mode/)
    assert.match(verifyProdEnv, /TRADETRAXS_PROD_PERF_FIFTY must be yes for fifty mode/)
    assert.match(verifyProdEnv, /LOADTEST_PROD_PERF_MODE" == "seventyfive" \|\| "\$LOADTEST_PROD_PERF_MODE" == "hundred"/)
    assert.match(
      verifyProdEnv,
      /onefifty" \|\| "\$LOADTEST_PROD_PERF_MODE" == "realistic150" \|\| "\$LOADTEST_PROD_PERF_MODE" == "realistic300"/
    )
    assert.match(verifyProdEnv, /mode requires exactly 50 dedicated users in LOADTEST_USERS_JSON/)
    assert.match(prodScript, /onefifty:[\s\S]*minUsers: 50/)
    assert.match(k6Summary, /appendRunTimingBreakdown/)
    assert.match(prodScript, /tradetraxs_setup_wall_ms/)
    assert.match(
      verifyProdEnv,
      /LOADTEST_PROD_PERF_MODE" == "twentyfive" \|\| "\$LOADTEST_PROD_PERF_MODE" == "fifty"/
    )
    assert.match(k6Diagnostics, /tradetraxs_ok_duration/)
    assert.match(prodScript, /constant-vus/)
    assert.doesNotMatch(prodScript, /rpc_v2_messaging_bootstrap/)
    assert.doesNotMatch(prodScript, /leaderboard/)
    assert.match(prodFullScript, /TRADETRAXS_PROD_PERF_REALISTIC300_FULL/)
    assert.match(prodFullScript, /LOADTEST_REALISTIC300_FULL_FIXTURE_JSON/)
    assert.match(messagingWorkloadProd, /rpc_v2_messaging_bootstrap/)
    assert.doesNotMatch(prodFullScript, /leaderboard/)
    assert.match(sendBudget, /vuAllowanceFromGlobalPartition/)
    assert.match(sendBudget, /LOADTEST_FULL_MAX_DM_SENDS_TOTAL/)
    assert.match(cleanupScript, /assertScopedQuery/)
    assert.match(cleanupScript, /conversation_id=eq\./)
    assert.match(cleanupScript, /content=like\./)
    assert.match(cleanupScript, /realistic600_full/)
    assert.match(cleanupScript, /realistic1000_full/)
    assert.match(cleanupScript, /--realistic1000/)
    assert.match(prod600FullScript, /LOADTEST_REALISTIC600_USERS_JSON/)
    assert.match(prod600FullScript, /LOADTEST_REALISTIC600_FULL_FIXTURE_JSON/)
    assert.match(prod600FullScript, /buildVuUserIndexEven/)
    assert.match(prod600FullScript, /REQUIRED_DM_SENDS_TOTAL = 400/)
    assert.match(prod600FullScript, /setupTimeout:\s*"12m"/)
    assert.match(prod600FullScript, /LOADTEST_K6_SETUP_AUTH_SPACING_SEC/)
    assert.match(workloadProd, /loginPasswordGrantDetailedWithRetry/)
    assert.match(
      read("loadtest/lib/read-workload-realistic300-full.js"),
      /runCorrelatedDeliverySession/
    )
    assert.match(read("loadtest/lib/realtime-phoenix.js"), /pendingJoins/)
    assert.match(read("loadtest/lib/realtime-phoenix.js"), /matchesCorrelatedDelivery/)
    assert.match(read("loadtest/lib/k6-summary.js"), /snapshotActivityMix/)
    assert.match(read("loadtest/lib/realistic300-full-activities.js"), /tradetraxs_activity_" \+ id/)
    assert.match(prod600FullScript, /runRealistic300FullIteration/)
    assert.match(prod1000FullScript, /TRADETRAXS_PROD_PERF_REALISTIC1000_FULL/)
    assert.match(prod1000FullScript, /REQUIRED_DM_SENDS_TOTAL = 700/)
    assert.match(prod1000FullScript, /REQUIRED_ROOM_SENDS_TOTAL = 700/)
    assert.match(prod1000FullScript, /MAX_VUS = 1000/)
    assert.match(prod1000FullScript, /realistic1000_full/)
    assert.match(prod1000FullScript, /realistic1000-full-last-summary\.json/)
    assert.match(prod1000FullScript, /VUS_PER_USER = MAX_VUS \/ REQUIRED_USER_COUNT/)
    assert.match(prod1000FullScript, /buildVuUserIndexEven/)
    assert.match(prod1000FullScript, /\[loadtest:realistic1000_full\]/)
    assert.match(read("loadtest/lib/realistic1000-full-tag.js"), /realistic1000_full/)
    assert.match(read("loadtest/scripts/run-realistic1000-full.sh"), /prod-realistic1000-full\.js/)
    assert.match(k6Summary, /computeSendCapUtilization/)
    assert.match(k6Summary, /allowanceUnused/)
    assert.match(read("loadtest/lib/realistic300-full-send-budget.js"), /tradetraxs_global_dm_allowance_consumed/)
    assert.match(k6Summary, /profile\.messageTag/)
    assert.match(messagingWorkloadProd, /getLoadtestMessageTag/)
  })

  it("keeps staging script isolated from production", () => {
    assert.match(stagingScript, /LOADTEST_ENV !== "staging"/)
    assert.match(stagingScript, /runStagingReadPreflight/)
    assert.match(workloadStaging, /rpc_v2_messaging_bootstrap/)
    assert.doesNotMatch(workloadProd, /rpc_v2_messaging_bootstrap/)
  })
})
