import { describe, it } from "node:test"
import assert from "node:assert/strict"
import { TRADES_ANALYTICS_FIELDS } from "./publicAccountPrivacy.ts"
import { computeMaxDrawdown } from "./dashboardMaxDrawdown.ts"
import { computeLongShortPerformance } from "./dashboardLongShortStats.ts"
import { computeHoldTimeStats } from "./dashboardHoldTimeStats.ts"
import {
  getDashboardTradingDayKey,
  tradeMatchesDashboardTimeFilter,
} from "./dashboardTradeDate.ts"
import { tradeMatchesAccountFilter } from "./tradeAccountDisplay.ts"
import { excludeBacktestTrades } from "./tradeModeFilters.ts"
import { computePeriodTradeStats } from "./periodTradeStats.ts"
import { getTradingDayKey, resolveTradingTimeSourceForKey } from "./formatDate.ts"
import { averageRrFromTrades } from "./tradeRr.ts"

type Row = Record<string, unknown>

function project(row: Row): Row {
  const next: Row = {}
  for (const key of TRADES_ANALYTICS_FIELDS) {
    if (key in row) next[key] = row[key]
  }
  return next
}

const wideTrades: Row[] = [
  {
    id: "a",
    user_id: "u",
    created_at: "2026-03-02T15:00:00.000Z",
    date: "2026-03-02",
    entry_time: "2026-03-02T14:30:00.000Z",
    exit_time: "2026-03-02T15:00:00.000Z",
    pnl: 200,
    rr: 2,
    direction: "Long",
    ticker: "ES",
    strategy: "ORB",
    session: "New York",
    account_id: "acc-live",
    account_name: "Live",
    account_size: "10000",
    account_type: "live",
    mode: "live",
    is_public: false,
    public_description: "Posted anyway",
    duration_seconds: 1800,
    points: 8,
    contracts: 2,
    entry_price: 5000,
    exit_price: 5008,
    notes: "private journal",
    psychology_notes: "hesitated",
    image_url: "https://cdn.example.com/a.jpg",
  },
  {
    id: "b",
    user_id: "u",
    created_at: "2026-03-02T23:30:00.000Z",
    date: "2026-03-02",
    entry_time: "2026-03-02T23:30:00.000Z",
    exit_time: "2026-03-02T23:45:00.000Z",
    pnl: -80,
    rr: 0.5,
    direction: "Short",
    ticker: "NQ",
    strategy: "VWAP",
    session: "Asia",
    account_id: "acc-eval",
    account_name: "Eval",
    account_size: "50000",
    account_type: "eval",
    mode: "eval",
    is_public: true,
    public_description: "",
    duration_seconds: 900,
    points: -4,
    contracts: 1,
    entry_price: 18000,
    exit_price: 18004,
    notes: "late entry",
    psychology_notes: "",
    image_url: "https://cdn.example.com/b.jpg",
  },
  {
    id: "c",
    user_id: "u",
    created_at: "2026-03-10T16:00:00.000Z",
    date: "2026-03-10",
    entry_time: "2026-03-10T16:00:00.000Z",
    exit_time: "2026-03-10T16:20:00.000Z",
    pnl: 40,
    rr: 1,
    direction: "Long",
    ticker: "ES",
    strategy: "ORB",
    session: "New York",
    account_id: "acc-live",
    account_name: "Live",
    account_size: "10000",
    account_type: "funded",
    mode: "funded",
    is_public: false,
    public_description: "",
    duration_seconds: 1200,
    points: 2,
    contracts: 3,
    entry_price: 5100,
    exit_price: 5102,
    notes: "",
    psychology_notes: "followed plan",
    image_url: null,
  },
  {
    id: "d",
    user_id: "u",
    created_at: "2026-01-15T15:00:00.000Z",
    date: "2026-01-15",
    entry_time: "2026-01-15T15:00:00.000Z",
    exit_time: "2026-01-15T15:05:00.000Z",
    pnl: 500,
    rr: 3,
    direction: "Long",
    ticker: "ES",
    strategy: "Backtest",
    session: "New York",
    account_id: "acc-bt",
    account_name: "Sim",
    account_size: "150000",
    account_type: "backtest",
    mode: "backtest",
    is_public: false,
    public_description: "",
    duration_seconds: 300,
    points: 10,
    contracts: 1,
    entry_price: 4900,
    exit_price: 4910,
    notes: "exclude from dashboard",
    psychology_notes: "",
    image_url: null,
  },
]

function tradeIsPublic(trade: Row) {
  if (trade.is_public === true) return true
  const desc = trade.public_description
  return typeof desc === "string" && desc.trim().length > 0
}

function summarize(trades: Row[]) {
  const journal = excludeBacktestTrades(trades as never) as Row[]
  const accountFiltered = journal.filter((trade) =>
    tradeMatchesAccountFilter(trade as never, "Live|10000|acc-live", {
      id: "acc-live",
      name: "Live",
      account_size: "10000",
    })
  )
  const modeFiltered = journal.filter(
    (trade) => String(trade.mode ?? trade.account_type) === "eval"
  )
  const publicOnly = journal.filter((trade) => tradeIsPublic(trade as Row))
  const now = new Date("2026-03-12T16:00:00.000Z")
  const monthly = journal.filter((trade) =>
    tradeMatchesDashboardTimeFilter(trade as never, "monthly", now, "", "")
  )
  const chronological = [...journal].sort(
    (a, b) =>
      new Date(String(a.entry_time ?? a.created_at)).getTime() -
      new Date(String(b.entry_time ?? b.created_at)).getTime()
  )
  let equity = 0
  const equityCurve = chronological.map((trade) => {
    equity += Number(trade.pnl) || 0
    return {
      date: getDashboardTradingDayKey(trade as never),
      equity,
    }
  })
  const dayTotals = new Map<string, number>()
  for (const trade of journal) {
    const resolved = resolveTradingTimeSourceForKey(trade as never)
    const key = resolved ? getTradingDayKey(resolved) : null
    if (!key) continue
    dayTotals.set(key, (dayTotals.get(key) ?? 0) + (Number(trade.pnl) || 0))
  }
  const wins = journal.filter((trade) => (Number(trade.pnl) || 0) > 0)
  const losses = journal.filter((trade) => (Number(trade.pnl) || 0) < 0)
  const grossWin = wins.reduce((sum, trade) => sum + (Number(trade.pnl) || 0), 0)
  const grossLoss = Math.abs(
    losses.reduce((sum, trade) => sum + (Number(trade.pnl) || 0), 0)
  )
  const weekday = new Map<string, number>()
  const hours = new Map<number, number>()
  for (const trade of journal) {
    const key = getDashboardTradingDayKey(trade as never)
    if (key) {
      const day = new Date(`${key}T16:00:00.000Z`).getUTCDay()
      weekday.set(String(day), (weekday.get(String(day)) ?? 0) + (Number(trade.pnl) || 0))
    }
    const hour = new Date(String(trade.entry_time)).getUTCHours()
    hours.set(hour, (hours.get(hour) ?? 0) + (Number(trade.pnl) || 0))
  }

  return {
    totalPnl: journal.reduce((sum, trade) => sum + (Number(trade.pnl) || 0), 0),
    winRate: journal.length ? wins.length / journal.length : 0,
    profitFactor: grossLoss > 0 ? grossWin / grossLoss : null,
    expectancy:
      journal.length === 0
        ? 0
        : (wins.length / journal.length) * (wins.length ? grossWin / wins.length : 0) -
          (losses.length / journal.length) *
            (losses.length ? grossLoss / losses.length : 0),
    equityCurve,
    maxDrawdown: computeMaxDrawdown(journal as never),
    longShort: computeLongShortPerformance(journal as never),
    holdTime: computeHoldTimeStats(journal as never),
    sessions: journal.map((trade) => trade.session),
    weekday: [...weekday.entries()],
    hours: [...hours.entries()],
    accountFiltered: accountFiltered.map((trade) => trade.id),
    modeFiltered: modeFiltered.map((trade) => trade.id),
    publicOnly: publicOnly.map((trade) => trade.id),
    monthly: monthly.map((trade) => trade.id),
    dayTotals: [...dayTotals.entries()],
    averageRr: averageRrFromTrades(journal as never),
    period: computePeriodTradeStats(journal as never),
  }
}

describe("dashboard and calendar narrow history parity", () => {
  it("matches wide-history calculations after the analytics projection", () => {
    const wide = summarize(wideTrades)
    const narrow = summarize(wideTrades.map(project))
    assert.deepEqual(narrow, wide)
  })

  it("calendar week and month totals use the same trading-day keys", () => {
    function calendarTotals(trades: Row[]) {
      const days = new Map<string, number>()
      for (const trade of trades) {
        const resolved = resolveTradingTimeSourceForKey(trade as never)
        if (!resolved) continue
        const key = getTradingDayKey(resolved)
        if (!key) continue
        days.set(key, (days.get(key) ?? 0) + (Number(trade.pnl) || 0))
      }
      const week = [...days.entries()]
        .filter(([key]) => key >= "2026-03-01" && key <= "2026-03-07")
        .reduce((sum, [, pnl]) => sum + pnl, 0)
      const month = [...days.entries()]
        .filter(([key]) => key.startsWith("2026-03"))
        .reduce((sum, [, pnl]) => sum + pnl, 0)
      return { days: [...days.entries()], week, month }
    }

    assert.deepEqual(
      calendarTotals(wideTrades.map(project)),
      calendarTotals(wideTrades)
    )
  })

  it("measures narrow versus wide JSON size on a repeated journal fixture", () => {
    const sample = {
      ...wideTrades[0],
      notes: "n".repeat(400),
      psychology_notes: "p".repeat(240),
      image_url:
        "https://cdn.example.com/storage/v1/object/public/trade-images/user/screenshot-001.jpg",
      public_description: "Shared recap of the opening drive.",
    }
    const sizes: Record<string, { wide: number; narrow: number }> = {}
    for (const count of [100, 1000, 10000]) {
      const wide = Array.from({ length: count }, (_, index) => ({
        ...sample,
        id: `t-${index}`,
      }))
      const narrow = wide.map(project)
      sizes[String(count)] = {
        wide: Buffer.byteLength(JSON.stringify(wide)),
        narrow: Buffer.byteLength(JSON.stringify(narrow)),
      }
      assert.ok(sizes[String(count)].narrow < sizes[String(count)].wide)
      assert.equal(JSON.stringify(narrow).includes("psychology_notes"), false)
      assert.equal(JSON.stringify(narrow).includes("image_url"), false)
      assert.equal("notes" in narrow[0], false)
    }
    console.log("ANALYTICS_FIXTURE_JSON_BYTES", JSON.stringify(sizes))
  })
})
