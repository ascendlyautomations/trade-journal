import { describe, it, beforeEach } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

describe("Phase H1 — Calendar ownership", () => {
  it("calendar page uses canonical appDataCache hooks only", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../app/calendar/page.tsx"),
      "utf8"
    )
    assert.match(src, /useCachedTrades/)
    assert.match(src, /useCachedAccounts/)
    assert.doesNotMatch(src, /\.from\("trades"\)/)
    assert.doesNotMatch(src, /\.from\("accounts"\)/)
    assert.doesNotMatch(src, /rpc_v1_calendar_bootstrap/)
  })

  it("ensureTradesLoaded short-circuits when trades cache is populated", () => {
    const src = fs.readFileSync(path.join(__dirname, "appDataCache.ts"), "utf8")
    assert.match(src, /if \(cached && !options\?\.force\)/)
    assert.match(src, /return cached/)
    assert.match(src, /fullHistory/)
  })

  it("calendar cold direct navigation still uses canonical ensureTradesLoaded path", () => {
    const hook = fs.readFileSync(path.join(__dirname, "useAppDataCache.ts"), "utf8")
    assert.match(hook, /ensureTradesLoaded/)
    assert.match(hook, /ensureAccountsLoaded/)
  })
})

describe("Phase H1 — Trades ownership", () => {
  it("trades page uses cached trades/accounts and bounded reels lookup", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../app/(app)/trades/page.tsx"),
      "utf8"
    )
    assert.match(src, /useCachedTrades/)
    assert.match(src, /useCachedAccounts/)
    assert.match(src, /displayedTrades/)
    assert.match(src, /fetchReelsByTradeIds/)
    assert.doesNotMatch(src, /rpc_v1_trades_page_bootstrap/)
    assert.doesNotMatch(src, /\.from\("trades"\)/)
  })

  it("reels module single-flights identical trade id sets and caches results", () => {
    const src = fs.readFileSync(path.join(__dirname, "reels.ts"), "utf8")
    assert.match(src, /getReelsByTradeIdsInflight\(cacheKey\)/)
    assert.match(src, /readReelsByTradeIdsCache\(cacheKey\)/)
    assert.match(src, /if \(inflight && !options\?\.force\) return inflight/)
  })

  it("reels query uses bounded trade_id list", () => {
    const src = fs.readFileSync(path.join(__dirname, "reels.ts"), "utf8")
    assert.match(src, /\.in\("trade_id", ids\)/)
  })
})

describe("Phase H1 — Dashboard bootstrap contract", () => {
  it("dashboard repository keeps single rpc ownership", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "backendV2/dashboardBootstrapRepository.ts"),
      "utf8"
    )
    assert.match(src, /DASHBOARD_TRADE_LIMIT = 500/)
    assert.match(src, /BackendV2RpcNames\.dashboard/)
    assert.match(src, /seedAppCachesFromDashboard/)
  })

  it("dashboard page recomputes analytics from cached trades", () => {
    const page = fs.readFileSync(
      path.join(__dirname, "../app/(app)/dashboard/page.tsx"),
      "utf8"
    )
    const analytics = fs.readFileSync(
      path.join(__dirname, "../app/(app)/dashboard/useDashboardAnalytics.ts"),
      "utf8"
    )
    assert.match(page, /useCachedTrades/)
    assert.match(page, /useDashboardAnalytics/)
    assert.doesNotMatch(page, /bootstrap\.data\.metrics/)
    assert.match(analytics, /deferredTradesExcludingBacktest/)
  })
})

describe("Phase H1 — Prop firm page wiring", () => {
  it("prop firm page gates legacy fan-out behind flag fallback", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../app/(app)/analytics/propfirm/page.tsx"),
      "utf8"
    )
    assert.match(src, /isBackendV2Enabled\("propFirm"\)/)
    assert.match(src, /loadPropFirmBootstrapForUser/)
    assert.match(src, /isPropFirmRpcUnavailable/)
    assert.match(src, /propFirmV2Active/)
  })

  it("legacy payout loader uses set-based account ids query", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "propfirmPayoutCycles.ts"),
      "utf8"
    )
    assert.match(src, /\.in\("account_id", uniqueIds\)/)
    assert.doesNotMatch(src, /Promise\.all\([\s\S]*fetchPayoutCycleHistory/)
  })
})
export {}
