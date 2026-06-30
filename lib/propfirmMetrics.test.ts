const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  buildDailyPnLMap,
  buildPropfirmEquityCurveData,
  buildPropfirmEquityEvents,
  computePropfirmAccountMetrics,
  computePropfirmEquityCurveYDomain,
  computePropfirmEquityCurveYTicks,
  computeConsistencyRule,
  computeDailyMetrics,
  computePayoutDrawdownFloor,
  computeTrailingDrawdown,
  countWinningDays,
  dedupeTradesById,
  getPropfirmTradingDay,
  isWinningTradingDay,
  replayPropfirmEquityEvents,
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

  it("starts from an initial drawdown floor after payout", () => {
    const trades = [{ id: "1", pnl: 250, created_at: "2024-06-10T10:00:00Z" }]
    const result = computeTrailingDrawdown(trades, 50250, 1000, {
      accountBaseBalance: 50000,
      initialDrawdownFloor: 50000,
      lockDrawdownFloor: true,
    })
    assert.equal(result.currentBalance, 50500)
    assert.equal(result.drawdownFloor, 50000)
    assert.equal(result.distanceToDD, 500)
  })

  it("keeps a trailing floor from before payout when specified", () => {
    const result = computeTrailingDrawdown([], 50250, 1000, {
      accountBaseBalance: 50000,
      initialDrawdownFloor: 49500,
    })
    assert.equal(result.currentBalance, 50250)
    assert.equal(result.drawdownFloor, 49500)
    assert.equal(result.distanceToDD, 750)
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
    assert.equal(result.ruleActive, true)
  })

  it("passes when rule inactive", () => {
    const trades = [{ pnl: 1000 }]
    const result = computeConsistencyRule(trades, 0)
    assert.equal(result.ruleActive, false)
    assert.equal(result.isConsistent, true)
  })

  it("treats null consistency as does not apply", () => {
    const trades = [{ pnl: 1000 }]
    const result = computeConsistencyRule(trades, null)
    assert.equal(result.ruleActive, false)
    assert.equal(result.isConsistent, true)
    assert.equal(result.allowedMax, 0)
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

  it("applies winning day threshold to daily net P/L", () => {
    const trades = [
      { trade_date: "2024-06-03", pnl: 199 },
      { trade_date: "2024-06-04", pnl: 200 },
      { trade_date: "2024-06-05", pnl: 250 },
    ]
    const metrics = computeDailyMetrics(
      trades,
      new Date("2024-06-05T15:00:00Z"),
      200
    )
    assert.equal(metrics.winningDays, 2)
  })

  it("defaults to positive daily net P/L when threshold is unset", () => {
    const trades = [{ trade_date: "2024-06-03", pnl: 1 }]
    const metrics = computeDailyMetrics(trades)
    assert.equal(metrics.winningDays, 1)
    assert.equal(isWinningTradingDay(1, null), true)
    assert.equal(isWinningTradingDay(0, null), false)
    assert.equal(countWinningDays({ "2024-06-03": 199 }, 200), 0)
    assert.equal(countWinningDays({ "2024-06-03": 200 }, 200), 1)
  })
})

describe("buildPropfirmEquityCurveData", () => {
  it("steps downward at payout events and preserves prior trade gains", () => {
    const trades = [
      {
        id: "1",
        trade_date: "2024-06-01",
        entry_time: null,
        created_at: "2024-06-01T12:00:00Z",
        pnl: 2000,
      },
      {
        id: "2",
        trade_date: "2024-06-10",
        entry_time: null,
        created_at: "2024-06-10T12:00:00Z",
        pnl: 600,
      },
      {
        id: "3",
        trade_date: "2024-06-12",
        entry_time: null,
        created_at: "2024-06-12T12:00:00Z",
        pnl: 1200,
      },
    ]
    const payouts = [{ endedAt: "2024-06-09T18:00:00.000Z", amount: 1500 }]

    const curve = buildPropfirmEquityCurveData(trades, 50000, payouts)
    const balances = curve.map((point) => point.balance)

    assert.deepEqual(balances, [50000, 52000, 50500, 51100, 52300])
    assert.equal(curve[2].pnl, -1500)
  })

  it("creates multiple downward steps for multiple payouts", () => {
    const trades = [
      {
        id: "1",
        trade_date: "2024-06-01",
        entry_time: null,
        created_at: "2024-06-01T12:00:00Z",
        pnl: 1000,
      },
      {
        id: "2",
        trade_date: "2024-06-15",
        entry_time: null,
        created_at: "2024-06-15T12:00:00Z",
        pnl: 800,
      },
      {
        id: "3",
        trade_date: "2024-06-20",
        entry_time: null,
        created_at: "2024-06-20T12:00:00Z",
        pnl: 500,
      },
    ]
    const payouts = [
      { endedAt: "2024-06-08T18:00:00.000Z", amount: 500 },
      { endedAt: "2024-06-18T18:00:00.000Z", amount: 700 },
    ]

    const curve = buildPropfirmEquityCurveData(trades, 50000, payouts)
    const payoutSteps = curve.filter((point) => point.pnl < 0)

    assert.equal(payoutSteps.length, 2)
    assert.equal(payoutSteps[0].balance, 50500)
    assert.equal(payoutSteps[1].balance, 50600)
  })

  it("ends at the displayed current account balance after payout cycles", () => {
    const trades = [
      {
        id: "1",
        trade_date: "2024-06-01",
        entry_time: null,
        created_at: "2024-06-01T12:00:00Z",
        pnl: 1500,
      },
      {
        id: "2",
        trade_date: "2024-06-10",
        entry_time: null,
        created_at: "2024-06-10T12:00:00Z",
        pnl: 200,
      },
    ]
    const account = {
      account_size: "50K",
      max_drawdown: 1000,
      profit_target: 3000,
      winning_days: 5,
    }
    const payouts = [{ endedAt: "2024-06-09T00:00:00.000Z", amount: 1250 }]
    const metrics = computePropfirmAccountMetrics(trades, account, {
      startedAt: "2024-06-09T00:00:00.000Z",
      cycleStartBalance: 50250,
      initialDrawdownFloor: 50000,
      drawdownBehavior: "reset_to_account",
      cycleNumber: 1,
    })
    const curve = buildPropfirmEquityCurveData(
      trades,
      metrics.startingBalance,
      payouts
    )

    assert.equal(curve[curve.length - 1].balance, metrics.displayCurrentBalance)
  })

  it("does not emit duplicate consecutive points", () => {
    const events = buildPropfirmEquityEvents([], [])
    const curve = replayPropfirmEquityEvents(50000, events)

    assert.deepEqual(curve, [{ date: "Start", balance: 50000, pnl: 0 }])
  })
})

describe("computePropfirmEquityCurveYDomain", () => {
  it("pads plotted balances by 500 when movement is at least 500", () => {
    const domain = computePropfirmEquityCurveYDomain([48250, 51300])
    assert.deepEqual(domain, [47750, 51800])
  })

  it("pads large-account balances the same way", () => {
    const domain = computePropfirmEquityCurveYDomain([148900, 150800])
    assert.deepEqual(domain, [148400, 151300])
  })

  it("centers a 1000 range when equity movement is under 500", () => {
    const domain = computePropfirmEquityCurveYDomain([50000, 50200])
    assert.deepEqual(domain, [49600, 50600])
  })

  it("includes reference-line values without anchoring to account size", () => {
    const domain = computePropfirmEquityCurveYDomain([49900, 50100], {
      includeValues: [53000, 48000],
    })
    assert.deepEqual(domain, [47500, 53500])
  })

  it("centers a 1000 range for a flat equity line", () => {
    const domain = computePropfirmEquityCurveYDomain([50000])
    assert.deepEqual(domain, [49500, 50500])
  })
})

describe("computePayoutDrawdownFloor", () => {
  it("resets drawdown floor to the account base", () => {
    const before = computeTrailingDrawdown(
      [{ id: "1", pnl: 1500, created_at: "2024-06-01T10:00:00Z" }],
      50000,
      1000
    )
    const floor = computePayoutDrawdownFloor(
      "reset_to_account",
      50000,
      before,
      1000
    )
    assert.equal(floor, 50000)
  })

  it("keeps the previous trailing floor", () => {
    const before = computeTrailingDrawdown(
      [{ id: "1", pnl: 1500, created_at: "2024-06-01T10:00:00Z" }],
      50000,
      1000
    )
    const floor = computePayoutDrawdownFloor(
      "keep_trailing",
      50000,
      before,
      1000
    )
    assert.equal(floor, before.drawdownFloor)
  })
})

describe("computePropfirmEquityCurveYTicks", () => {
  it("uses rounded 500/1000 steps for typical domains", () => {
    const ticks = computePropfirmEquityCurveYTicks([47750, 51800])
    assert.deepEqual(ticks, [47000, 48000, 49000, 50000, 51000, 52000])
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
    assert.equal(metrics.lifetimeTotalPnL, 75)
    assert.equal(metrics.cyclePnL, 75)
    assert.equal(metrics.cycleDailyMetrics.winningDays, 1)
    assert.equal(metrics.lifetimeTrailingMetrics.currentBalance, 50075)
    assert.equal(metrics.cycleTrailingMetrics.currentBalance, 50075)
    assert.equal(metrics.cycleConsistencyMetrics.ruleActive, true)
    assert.equal(metrics.cycleProgress.status, "IN PROGRESS")
  })

  it("resets payout-cycle metrics after a recorded payout boundary", () => {
    const trades = [
      {
        id: "1",
        trade_date: "2024-06-01",
        entry_time: null,
        created_at: "2024-06-01T12:00:00Z",
        pnl: 3000,
      },
      {
        id: "2",
        trade_date: "2024-06-05",
        entry_time: null,
        created_at: "2024-06-05T12:00:00Z",
        pnl: 500,
      },
      {
        id: "3",
        trade_date: "2024-06-06",
        entry_time: null,
        created_at: "2024-06-06T12:00:00Z",
        pnl: 200,
      },
    ]
    const account = {
      account_size: "50K",
      consistency: 50,
      max_drawdown: 2000,
      profit_target: 3000,
      winning_days: 5,
    }

    const lifetime = computePropfirmAccountMetrics(trades, account)
    assert.equal(lifetime.lifetimeTotalPnL, 3700)
    assert.equal(lifetime.lifetimeTrailingMetrics.currentBalance, 53700)
    assert.equal(lifetime.cycleDailyMetrics.winningDays, 3)

    const afterPayout = computePropfirmAccountMetrics(trades, account, {
      startedAt: "2024-06-05T00:00:00.000Z",
      cycleStartBalance: 53000,
    })

    assert.equal(afterPayout.lifetimeTotalPnL, 3700)
    assert.equal(afterPayout.lifetimeTrailingMetrics.currentBalance, 53700)
    assert.equal(afterPayout.displayCurrentBalance, 53700)
    assert.equal(afterPayout.cyclePnL, 700)
    assert.equal(afterPayout.cycleDailyMetrics.winningDays, 2)
    assert.equal(afterPayout.cycleProgress.status, "IN PROGRESS")
    assert.equal(afterPayout.cycleProgress.progressPercent, (700 / 3000) * 100)
  })

  it("resets winning days to zero immediately after payout timestamp", () => {
    const trades = [
      {
        id: "1",
        trade_date: "2024-06-05",
        entry_time: "2024-06-05T10:00:00Z",
        created_at: "2024-06-05T10:00:00Z",
        pnl: 500,
      },
      {
        id: "2",
        trade_date: "2024-06-05",
        entry_time: "2024-06-05T15:00:00Z",
        created_at: "2024-06-05T15:00:00Z",
        pnl: 300,
      },
    ]
    const account = {
      account_size: "50K",
      max_drawdown: 2000,
      profit_target: 3000,
      winning_days: 5,
    }

    const beforePayout = computePropfirmAccountMetrics(trades, account)
    assert.equal(beforePayout.cycleDailyMetrics.winningDays, 1)

    const afterPayout = computePropfirmAccountMetrics(trades, account, {
      startedAt: "2024-06-05T16:00:00.000Z",
      cycleStartBalance: 50800,
    })

    assert.equal(afterPayout.lifetimeTotalPnL, 800)
    assert.equal(afterPayout.cycleDailyMetrics.winningDays, 0)
    assert.equal(afterPayout.cyclePnL, 0)
    assert.equal(afterPayout.displayCurrentBalance, 50800)
    assert.equal(afterPayout.lifetimeTrailingMetrics.currentBalance, 50800)
  })

  it("uses post-payout balance anchor and drawdown floor for the active cycle", () => {
    const trades = [
      {
        id: "1",
        trade_date: "2024-06-01",
        entry_time: null,
        created_at: "2024-06-01T12:00:00Z",
        pnl: 1500,
      },
      {
        id: "2",
        trade_date: "2024-06-10",
        entry_time: null,
        created_at: "2024-06-10T12:00:00Z",
        pnl: 200,
      },
    ]
    const account = {
      account_size: "50K",
      max_drawdown: 1000,
      profit_target: 3000,
      winning_days: 5,
    }

    const lifetime = computePropfirmAccountMetrics(trades, account)
    assert.equal(lifetime.lifetimeTotalPnL, 1700)
    assert.equal(lifetime.lifetimeTrailingMetrics.currentBalance, 51700)

    const afterPayout = computePropfirmAccountMetrics(trades, account, {
      startedAt: "2024-06-09T00:00:00.000Z",
      cycleStartBalance: 50250,
      initialDrawdownFloor: 50000,
      drawdownBehavior: "reset_to_account",
      cycleNumber: 1,
    })

    assert.equal(afterPayout.lifetimeTotalPnL, 1700)
    assert.equal(afterPayout.displayCurrentBalance, 50450)
    assert.equal(afterPayout.cycleTrailingMetrics.drawdownFloor, 50000)
    assert.equal(afterPayout.cycleTrailingMetrics.distanceToDD, 450)
    assert.equal(afterPayout.cyclePnL, 200)
  })
})

describe("getPropfirmTradingDay", () => {
  it("returns null without trade_date", () => {
    assert.equal(getPropfirmTradingDay({}), null)
  })

  it("uses exit_time for futures session bucketing", () => {
    assert.equal(
      getPropfirmTradingDay({
        trade_date: "2024-06-03",
        entry_time: "2024-06-03T14:00:00-04:00",
        exit_time: "2024-06-03T22:00:00Z",
      }),
      "2024-06-04"
    )
  })

  it("assigns Sunday evening exit to Monday trading day", () => {
    assert.equal(
      getPropfirmTradingDay({
        trade_date: "2024-01-07",
        entry_time: "2024-01-08T00:00:00Z",
        exit_time: "2024-01-08T15:30:00Z",
      }),
      "2024-01-08"
    )
  })

  it("assigns Monday evening exit to Tuesday trading day", () => {
    assert.equal(
      getPropfirmTradingDay({
        trade_date: "2024-01-08",
        entry_time: "2024-01-08T20:00:00Z",
        exit_time: "2024-01-09T00:30:00Z",
      }),
      "2024-01-09"
    )
  })

  it("falls back to entry_time when exit_time is missing", () => {
    assert.equal(
      getPropfirmTradingDay({
        trade_date: "2024-06-03",
        entry_time: "2024-06-03T22:00:00Z",
      }),
      "2024-06-04"
    )
  })

  it("rolls time-only exit_time using trade_date", () => {
    assert.equal(
      getPropfirmTradingDay({
        trade_date: "2024-06-03",
        exit_time: "18:30:00",
      }),
      "2024-06-04"
    )
  })

  it("aggregates trades by exit-assigned futures day", () => {
    const trades = [
      {
        trade_date: "2024-01-07",
        entry_time: "2024-01-08T00:00:00Z",
        exit_time: "2024-01-08T15:30:00Z",
        pnl: 100,
      },
      {
        trade_date: "2024-01-08",
        entry_time: "2024-01-08T20:00:00Z",
        exit_time: "2024-01-09T00:30:00Z",
        pnl: 50,
      },
    ]
    const map = buildDailyPnLMap(trades)
    assert.equal(map["2024-01-08"], 100)
    assert.equal(map["2024-01-09"], 50)
  })
})
