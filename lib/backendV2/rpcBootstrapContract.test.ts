import { describe, it } from "node:test"
import { decodeSessionBootstrapV1, decodeDashboardBootstrapV1, } from "./contracts.ts"
import { validateSessionBootstrapContract, validateDashboardBootstrapContract, } from "./rpcContractSchema.ts"
import { sessionFixtures, dashboardFixtures, } from "./rpcContractFixtures.ts"
import { compareSessionBootstraps, } from "./sessionBootstrapCompare.ts"
import { compareDashboardBootstraps, } from "./dashboardBootstrapCompare.ts"
import { sessionBootstrapFixture, dashboardBootstrapFixture, } from "./fixtures.ts"
import assert from "node:assert/strict"

describe("Phase A — Session bootstrap contract shape", () => {
  const cases = [
    ["proWithAccounts", sessionFixtures.proWithAccounts],
    ["freeUser", sessionFixtures.freeUser],
    ["trialUser", sessionFixtures.trialUser],
    ["noAccounts", sessionFixtures.noAccounts],
    ["unreadMessages", sessionFixtures.unreadMessages],
    ["goldenFixture", sessionBootstrapFixture],
  ]

  for (const [name, fixture] of cases) {
    it(`validates ${name} fixture shape`, () => {
      const raw = JSON.parse(JSON.stringify(fixture))
      const decoded = decodeSessionBootstrapV1(raw)
      const violations = validateSessionBootstrapContract(decoded)
      assert.deepEqual(
        violations,
        [],
        `${name}: ${violations.map((v) => v.path).join(", ")}`
      )
    })
  }

  it("requires empty arrays not null for accounts_summary and following_ids", () => {
    const free = decodeSessionBootstrapV1(
      JSON.parse(JSON.stringify(sessionFixtures.freeUser))
    )
    assert.ok(Array.isArray(free.data.accounts_summary))
    assert.ok(Array.isArray(free.data.following_ids))
    assert.equal(free.data.accounts_summary.length, 0)
    assert.equal(free.data.following_ids.length, 0)
  })

  it("badges.rooms_unread is null not omitted", () => {
    const s = decodeSessionBootstrapV1(
      JSON.parse(JSON.stringify(sessionFixtures.proWithAccounts))
    )
    assert.equal(s.data.badges.rooms_unread, null)
  })

  it("compare helper detects entitlement drift", () => {
    const a = JSON.parse(JSON.stringify(sessionFixtures.proWithAccounts))
    const b = JSON.parse(JSON.stringify(sessionFixtures.proWithAccounts))
    b.data.viewer.entitlement.plan = "free"
    const mismatches = compareSessionBootstraps(
      decodeSessionBootstrapV1(a),
      decodeSessionBootstrapV1(b)
    )
    assert.ok(mismatches.some((m) => m.path === "viewer.entitlement.plan"))
  })
})

describe("Phase A — Dashboard bootstrap contract shape", () => {
  const cases = [
    ["withTrades", dashboardFixtures.withTrades],
    ["emptyTrades", dashboardFixtures.emptyTrades],
    ["noAccounts", dashboardFixtures.noAccounts],
    ["goldenFixture", dashboardBootstrapFixture],
  ]

  for (const [name, fixture] of cases) {
    it(`validates ${name} fixture shape`, () => {
      const raw = JSON.parse(JSON.stringify(fixture))
      const decoded = decodeDashboardBootstrapV1(raw)
      const violations = validateDashboardBootstrapContract(decoded)
      assert.deepEqual(
        violations,
        [],
        `${name}: ${violations.map((v) => v.path).join(", ")}`
      )
    })
  }

  it("empty state uses [] not null for trade arrays", () => {
    const d = decodeDashboardBootstrapV1(
      JSON.parse(JSON.stringify(dashboardFixtures.emptyTrades))
    )
    assert.deepEqual(d.data.trade_window, [])
    assert.deepEqual(d.data.recent_trades, [])
    assert.deepEqual(d.data.equity_points, [])
    assert.equal(d.data.trade_window_meta.oldest_created_at, null)
    assert.equal(d.data.metrics.win_rate, null)
  })

  it("trade_window_meta.next_cursor is null", () => {
    const d = decodeDashboardBootstrapV1(
      JSON.parse(JSON.stringify(dashboardFixtures.withTrades))
    )
    assert.equal(d.data.trade_window_meta.next_cursor, null)
  })

  it("compare helper detects metrics drift", () => {
    const a = JSON.parse(JSON.stringify(dashboardFixtures.withTrades))
    const b = JSON.parse(JSON.stringify(dashboardFixtures.withTrades))
    b.data.metrics.net_pnl = 999
    const mismatches = compareDashboardBootstraps(
      decodeDashboardBootstrapV1(a),
      decodeDashboardBootstrapV1(b)
    )
    assert.ok(mismatches.some((m) => m.path === "metrics.net_pnl"))
  })
})

describe("Phase A — independent bootstrap failure semantics (app layer)", () => {
  it("session decode succeeds without dashboard payload", () => {
    const session = decodeSessionBootstrapV1(
      JSON.parse(JSON.stringify(sessionFixtures.proWithAccounts))
    )
    assert.ok(session.data.viewer.id)
    assert.ok(!("trade_window" in session.data))
  })

  it("dashboard decode succeeds without session viewer payload", () => {
    const dash = decodeDashboardBootstrapV1(
      JSON.parse(JSON.stringify(dashboardFixtures.withTrades))
    )
    assert.ok(Array.isArray(dash.data.accounts))
    assert.ok(!("session_profile" in dash.data))
  })
})
export {}
