const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  LANDING_COMPARISON_COLUMNS,
  LANDING_COMPARISON_FEATURE_LABELS,
  LANDING_COMPARISON_ROWS,
} = require("./landingComparison.ts")
const { TRADETRAXS_PRO_PLAN } = require("./tradeTraxsPlans.ts")

describe("landingComparison", () => {
  it("rows follow recommended selling order", () => {
    const expected = [
      LANDING_COMPARISON_FEATURE_LABELS.aiTradeAnalyst,
      LANDING_COMPARISON_FEATURE_LABELS.propFirmMode,
      LANDING_COMPARISON_FEATURE_LABELS.communityTradeRooms,
      LANDING_COMPARISON_FEATURE_LABELS.performanceAnalytics,
      LANDING_COMPARISON_FEATURE_LABELS.tradeReplayVideos,
      LANDING_COMPARISON_FEATURE_LABELS.backtestLab,
      LANDING_COMPARISON_FEATURE_LABELS.unlimitedTradeJournaling,
      LANDING_COMPARISON_FEATURE_LABELS.multipleTradingAccounts,
      LANDING_COMPARISON_FEATURE_LABELS.screenshotUploads,
      LANDING_COMPARISON_FEATURE_LABELS.tradingReels,
      LANDING_COMPARISON_FEATURE_LABELS.directMessaging,
      LANDING_COMPARISON_FEATURE_LABELS.continuousUpdates,
    ]
    assert.deepEqual(
      LANDING_COMPARISON_ROWS.map((row) => row.feature),
      expected
    )
  })

  it("uses aggregated competitor columns only", () => {
    const labels = LANDING_COMPARISON_COLUMNS.map((col) => col.label).join(" ")
    assert.doesNotMatch(labels, /TradeZella/i)
    assert.doesNotMatch(labels, /TraderSync/i)
    assert.doesNotMatch(labels, /Discord/i)
    assert.match(labels, /Other Journals/)
    assert.match(labels, /Excel \/ Notion/)
  })

  it("reuses pricing plan names for core Pro features", () => {
    assert.equal(
      LANDING_COMPARISON_FEATURE_LABELS.aiTradeAnalyst,
      TRADETRAXS_PRO_PLAN.features[2]
    )
    assert.equal(
      LANDING_COMPARISON_FEATURE_LABELS.backtestLab,
      TRADETRAXS_PRO_PLAN.features[3]
    )
  })

  it("TradeTraxs supports every listed capability", () => {
    for (const row of LANDING_COMPARISON_ROWS) {
      assert.notEqual(row.tt, "none", row.feature)
    }
  })
})
