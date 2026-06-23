const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  buildDailyPnLMap,
  computePropfirmAccountMetrics,
  computePropfirmEquityCurveYDomain,
  computeConsistencyRule,
  computeDailyMetrics,
  computeTrailingDrawdown,
  dedupeTradesById,
  getPropfirmTradingDay,
} = require("./propfirmMetrics.ts")

describe("dedupeTradesById", () => {
  it("removes duplicate ids", () => {
    const trades = [
      { id: "a", pnl: 100 },
      { id: "a", pnl: 200 },
      { id: "b", pnl: 50 },
    ]
    const out = dedupeTradesById(trades)
    assert.equal(out.length, 2)
    assert.equal(out[0].pnl, 100)
  })
})

describe("computeTrailingDrawdown", () => {
  it("tracks peak and breach", () => {
    const trades = [
      { id: "1", pnl: 1000, created_at: "2024-01-01T10:00:00Z" },
      { id: "2", pnl: -2500, created_at: "2024-01-02T10:00:00Z" },
    ]
    const result = computeTrailingDrawdown(trades, 50000, 2000)
    assert.equal(result.peakBalance, 51000)
    assert.equal(result.currentBalance, 48500)
    assert.equal(result.maxDrawdownUsed, 2500)
    assert.equal(result.breachedTrailingDD, true)
  })

  it("raises drawdown floor on new peak only", () => {
    const trades = [
      { id: "1", pnl: 500, created_at: "2024-01-01T10:00:00Z" },
      { id: "2", pnl: 300, created_at: "2024-01-02T10:00:00Z" },
    ]
    const result = computeTrailingDrawdown(trades, 50000, 2000)
    assert.equal(result.peakBalance, 50800)
    assert.equal(result.drawdownFloor, 48800)
    assert.equal(result.breachedTrailingDD, false)
  })

  it("caps the trailing floor at the starting balance", () => {
    const trades = [
      { id: "1", pnl: 2000, created_at: "2024-01-01T10:00:00Z" },
      { id: "2", pnl: 1000, created_at: "2024-01-02T10:00:00Z" },
      { id: "3", pnl: -1500, created_at: "2024-01-03T10:00:00Z" },
    ]
    const result = computeTrailingDrawdown(trades, 50000, 2000)
    assert.equal(result.peakBalance, 53000)
    assert.equal(result.currentBalance, 51500)
    assert.equal(result.drawdownFloor, 50000)
    assert.equal(result.maxDrawdownUsed, 500)
    assert.equal(result.breachedTrailingDD, false)
  })

  it("detects breaches against the capped floor", () => {
    const trades = [
      { id: "1", pnl: 3000, created_at: "2024-01-01T10:00:00Z" },
      { id: "2", pnl: -3100, created_at: "2024-01-02T10:00:00Z" },
    ]
    const result = computeTrailingDrawdown(trades, 50000, 2000)
    assert.equal(result.drawdownFloor, 50000)
    assert.equal(result.currentBalance, 49900)
    assert.equal(result.breachedTrailingDD, true)
  })

  it("uses legacy created_at ordering", () => {
    const trades = [
      { id: "2", pnl: 1000, created_at: "2024-01-02T10:00:00Z" },
      { id: "1", pnl: -500, created_at: "2024-01-01T10:00:00Z" },
    ]
    const result = computeTrailingDrawdown(trades, 50000, 1000)
    assert.equal(result.peakBalance, 50500)
    assert.equal(result.drawdownFloor, 49500)
  })
})

describe("computeConsistencyRule", () => {
  it("fails when biggest win exceeds allowed percent", () => {
    const trades = [{ pnl: 300 }, { pnl: 200 }, { pnl: -50 }]
    const result = computeConsistencyRule(trades, 40)
    assert.equal(result.totalProfit, 500)
    assert.equal(result.biggestWin, 300)
    assert.equal(result.allowedMax, 200)
    assert.equal(result.isConsistent, false)
  })

  it("passes when rule inactive", () => {
    const trades = [{ pnl: 1000 }]
    const result = computeConsistencyRule(trades, 0)
    assert.equal(result.ruleActive, false)
    assert.equal(result.isConsistent, true)
  })
})

describe("daily aggregation", () => {
  it("buckets trades by propfirm trading day", () => {
    const trades = [
      { trade_date: "2024-06-03", entry_time: null, pnl: 100 },
      { trade_date: "2024-06-03", entry_time: null, pnl: -40 },
      { trade_date: "2024-06-04", entry_time: null, pnl: 25 },
    ]
    const map = buildDailyPnLMap(trades)
    assert.equal(map["2024-06-03"], 60)
    assert.equal(map["2024-06-04"], 25)
  })

  it("uses trade_date instead of import created_at for imported trades", () => {
    const trades = [
      {
        trade_date: "2024-05-01",
        entry_time: null,
        created_at: "2024-06-15T12:00:00Z",
        pnl: 100,
      },
      {
        trade_date: "2024-05-01",
        entry_time: null,
        created_at: "2024-06-15T12:01:00Z",
        pnl: 50,
      },
    ]
    const map = buildDailyPnLMap(trades)
    assert.equal(map["2024-05-01"], 150)
    assert.equal(map["2024-06-15"], undefined)
  })

  it("falls back to legacy CSV date when trade_date is missing", () => {
    const trades = [
      {
        date: "2024-05-01T14:30:00Z",
        trade_date: null,
        entry_time: null,
        created_at: "2024-06-15T12:00:00Z",
        pnl: 100,
      },
      {
        date: "2024-05-01T15:30:00Z",
        trade_date: null,
        entry_time: null,
        created_at: "2024-06-15T12:01:00Z",
        pnl: -25,
      },
    ]
    const map = buildDailyPnLMap(trades)
    assert.equal(map["2024-05-01"], 75)
    assert.equal(map["2024-06-15"], undefined)
  })

  it("computes winning days and worst day", () => {
    const trades = [
      { trade_date: "2024-06-03", pnl: 100 },
      { trade_date: "2024-06-04", pnl: -200 },
      { trade_date: "2024-06-05", pnl: 50 },
    ]
    const metrics = computeDailyMetrics(trades, new Date("2024-06-05T15:00:00Z"))
    assert.equal(metrics.winningDays, 2)
    assert.equal(metrics.worstDay, -200)
    assert.equal(metrics.worstDailyLossUsed, 200)
  })
})

describe("computePropfirmEquityCurveYDomain", () => {
  it("pads plotted balances by 300 when range is at least 150", () => {
    const domain = computePropfirmEquityCurveYDomain([49300, 51100])
    assert.deepEqual(domain, [49000, 51400])
  })

  it("pads large-account balances the same way", () => {
    const domain = computePropfirmEquityCurveYDomain([148900, 150800])
    assert.deepEqual(domain, [148600, 151100])
  })

  it("uses smaller padding when the plotted range is very tight", () => {
    const domain = computePropfirmEquityCurveYDomain([50000, 50100])
    assert.deepEqual(domain, [49850, 50250])
  })

  it("includes reference-line values without anchoring to account size", () => {
    const domain = computePropfirmEquityCurveYDomain([49900, 50100], {
      includeValues: [53000, 48000],
    })
    assert.deepEqual(domain, [47700, 53300])
  })

  it("prevents an inverted domain", () => {
    const domain = computePropfirmEquityCurveYDomain([50000])
    assert.deepEqual(domain, [49850, 50150])
  })
})

describe("computePropfirmAccountMetrics", () => {
  it("returns one deterministic metrics snapshot for the page", () => {
    const trades = [
      {
        id: "1",
        trade_date: "2024-06-03",
        entry_time: null,
        created_at: "2024-06-03T12:00:00Z",
        pnl: 100,
      },
      {
        id: "2",
        trade_date: "2024-06-04",
        entry_time: null,
        created_at: "2024-06-04T12:00:00Z",
        pnl: -25,
      },
    ]
    const account = {
      account_size: "50K",
      consistency: 50,
      max_drawdown: 2000,
      profit_target: 3000,
    }

    const metrics = computePropfirmAccountMetrics(trades, account)
    assert.equal(metrics.startingBalance, 50000)
    assert.equal(metrics.totalPnL, 75)
    assert.equal(metrics.dailyMetrics.winningDays, 1)
    assert.equal(metrics.trailingMetrics.currentBalance, 50075)
    assert.equal(metrics.consistencyMetrics.ruleActive, true)
    assert.equal(metrics.progress.status, "IN PROGRESS")
  })
})

describe("getPropfirmTradingDay", () => {
  it("returns null without trade_date", () => {
    assert.equal(getPropfirmTradingDay({}), null)
  })

  it("rolls the trading day after 6pm Eastern", () => {
    assert.equal(
      getPropfirmTradingDay({
        trade_date: "2024-06-03",
        entry_time: "2024-06-03T22:00:00Z",
      }),
      "2024-06-04"
    )
  })

  it("rolls time-only entry_time using trade_date", () => {
    assert.equal(
      getPropfirmTradingDay({
        trade_date: "2024-06-03",
        entry_time: "18:30:00",
      }),
      "2024-06-04"
    )
  })
})
