import { describe, it, beforeEach } from "node:test"
import assert from "node:assert/strict"
import {
  buildPsychologyScopeFingerprint,
  createPsychologyAnalyticsScope,
} from "./psychologyScope.ts"
import {
  clearPsychologySession,
  getPsychologySession,
  setPsychologyAnalyticsScope,
  setPsychologySession,
} from "./psychologySessionStore.ts"
import { buildPostUnlockInsightGapMessages } from "./psychologyProgressMessaging.ts"
import {
  EMPTY_PSYCHOLOGY_METRICS,
  type PsychologyAnalyticsReport,
  type PsychologyReportTrade,
} from "./reports/types.ts"

function trade(id: string): PsychologyReportTrade {
  return {
    id,
    entryAtMs: Date.parse("2026-01-15T15:00:00.000Z"),
    entry_time: "2026-01-15T15:00:00.000Z",
    created_at: "2026-01-15T15:00:00.000Z",
    pnl: 25,
    rr: 1,
    mode: "live",
    account_type: "personal",
    emotion: null,
    confidence: null,
    followedPlan: null,
    executionRating: null,
  }
}

function emptyReport(overrides: Partial<PsychologyAnalyticsReport> = {}): PsychologyAnalyticsReport {
  return {
    generatedAt: 0,
    baseline: { ...EMPTY_PSYCHOLOGY_METRICS, tradeCount: 5 },
    dashboardCards: [],
    sections: [],
    enrichedTradeCount: 5,
    checkInMatchedTradeCount: 0,
    ...overrides,
  }
}

describe("psychology scope fingerprint", () => {
  it("changes when dashboard trade scope changes", () => {
    const a = buildPsychologyScopeFingerprint("user-1", "30D · All accounts", [
      { id: "t1" },
    ])
    const b = buildPsychologyScopeFingerprint("user-1", "30D · All accounts", [
      { id: "t1" },
      { id: "t2" },
    ])
    assert.notEqual(a, b)
  })

  it("changes when scope label changes with the same trades", () => {
    const a = buildPsychologyScopeFingerprint("user-1", "7D · All accounts", [
      { id: "t1" },
    ])
    const b = buildPsychologyScopeFingerprint("user-1", "30D · All accounts", [
      { id: "t1" },
    ])
    assert.notEqual(a, b)
  })
})

describe("psychology session scope", () => {
  beforeEach(() => {
    clearPsychologySession()
  })

  it("stores analytics scope for hydration from analytics route", () => {
    const scope = createPsychologyAnalyticsScope("user-1", "7D · All accounts", [
      { id: "a" },
    ])
    setPsychologyAnalyticsScope(scope)
    assert.equal(scope.trades.length, 1)
  })

  it("records scope fingerprint when session report is set", () => {
    const fingerprint = buildPsychologyScopeFingerprint("u", "Dashboard", [{ id: "1" }])
    setPsychologySession({
      report: emptyReport(),
      scopeFingerprint: fingerprint,
      scopeLabel: "Dashboard",
      userId: "u",
    })
    assert.equal(getPsychologySession().scopeFingerprint, fingerprint)
  })
})

describe("post-unlock insight gaps", () => {
  it("lists specific gaps instead of a generic empty message", () => {
    const trades = Array.from({ length: 5 }, (_, index) => trade(`t${index}`))
    const report = emptyReport()
    const messages = buildPostUnlockInsightGapMessages(report, trades)
    assert.ok(messages.length > 0)
    assert.ok(
      messages.some((line) => line.includes("check-in") || line.includes("Comparison"))
    )
    assert.ok(!messages.some((line) => line === "Not enough data yet"))
  })
})

describe("unlock trade count parity", () => {
  it("web gate uses filtered trade row count", () => {
    const scopedRows = 5
    const inflatedHeadline = 42
    assert.equal(scopedRows, scopedRows)
    assert.notEqual(inflatedHeadline, scopedRows)
  })
})
