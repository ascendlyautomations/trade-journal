import { describe, it, beforeEach } from "node:test"
import { decodeDashboardBootstrapV1 } from "./contracts.ts"
import { dashboardBootstrapFixture } from "./fixtures.ts"
import { compareDashboardBootstraps, } from "./dashboardBootstrapCompare.ts"
import { writeDashboardBootstrapCache, readDashboardBootstrapCache, clearDashboardBootstrapCache, } from "./dashboardBootstrapCache.ts"
import { beginDashboardBootstrapFlight, __resetDashboardBootstrapFlightsForTests, } from "./dashboardBootstrapSingleFlight.ts"
import { isBackendV2Enabled, __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, } from "./flags.ts"
import assert from "node:assert/strict"

describe("Backend V2 dashboard bootstrap (Phase 3)", () => {
  beforeEach(() => {
    clearDashboardBootstrapCache()
    __resetDashboardBootstrapFlightsForTests()
    __resetBackendV2FlagsForTests()
  })

  it("decodes fixture with trade_window_meta", () => {
    const decoded = decodeDashboardBootstrapV1(
      JSON.parse(JSON.stringify(dashboardBootstrapFixture))
    )
    assert.equal(decoded.data.trade_window_meta.history_complete, true)
    assert.equal(decoded.data.accounts[0].name, "Main")
    assert.equal(decoded.data.metrics.total_trades, 1)
  })

  it("dashboard flag defaults OFF", () => {
    assert.equal(isBackendV2Enabled("dashboard"), false)
  })

  it("compare detects account id mismatch", () => {
    const rest = JSON.parse(JSON.stringify(dashboardBootstrapFixture))
    const rpc = JSON.parse(JSON.stringify(dashboardBootstrapFixture))
    rpc.data.accounts[0].id = "99999999-9999-9999-9999-999999999999"
    const mismatches = compareDashboardBootstraps(rest, rpc)
    assert.ok(mismatches.some((m) => m.path === "accounts.ids"))
  })

  it("cache is single-entry per user", () => {
    const uid = dashboardBootstrapFixture.meta.viewer_id
    assert.ok(uid)
    writeDashboardBootstrapCache(uid, dashboardBootstrapFixture, "rpc")
    assert.equal(
      readDashboardBootstrapCache(uid)?.data.payout_total,
      0
    )
  })

  it("single-flight shares one start", async () => {
    let starts = 0
    const [a, b] = await Promise.all([
      beginDashboardBootstrapFlight("d1", async () => {
        starts += 1
        await new Promise((r) => setTimeout(r, 15))
        return { ok: true }
      }),
      beginDashboardBootstrapFlight("d1", async () => {
        starts += 1
        return { ok: false }
      }),
    ])
    assert.equal(starts, 1)
    assert.equal(a.ok, true)
    assert.equal(b.ok, true)
  })

  it("env can enable dashboard flag", () => {
    __setBackendV2FlagForTests("dashboard", true)
    assert.equal(isBackendV2Enabled("dashboard"), true)
  })
})
export {}
