import { DEMO_USER_ID } from "./constants"
import { demoTradeScreenshotUrl } from "./demoAssets"
import { getTradingSession } from "@/lib/formatDate"

type BacktestSeed = {
  id: string
  daysAgo: number
  hour: number
  ticker: string
  pnl: number
  rr: number
  direction: "Long" | "Short"
  entry: number
  exit: number
  points: number
  contracts: number
  strategy: string
}

const BACKTEST_SEEDS: BacktestSeed[] = [
  {
    id: "bt-01",
    daysAgo: 28,
    hour: 10,
    ticker: "NQ",
    pnl: 620,
    rr: 2.4,
    direction: "Long",
    entry: 18720,
    exit: 18751,
    points: 31,
    contracts: 2,
    strategy: "Opening Drive",
  },
  {
    id: "bt-02",
    daysAgo: 26,
    hour: 9,
    ticker: "ES",
    pnl: -240,
    rr: 0.8,
    direction: "Short",
    entry: 5412,
    exit: 5418,
    points: -6,
    contracts: 2,
    strategy: "Opening Drive",
  },
  {
    id: "bt-03",
    daysAgo: 24,
    hour: 14,
    ticker: "NQ",
    pnl: 880,
    rr: 2.9,
    direction: "Long",
    entry: 18810,
    exit: 18854,
    points: 44,
    contracts: 2,
    strategy: "ICT Model",
  },
  {
    id: "bt-04",
    daysAgo: 21,
    hour: 11,
    ticker: "NQ",
    pnl: 410,
    rr: 1.7,
    direction: "Short",
    entry: 18905,
    exit: 18884,
    points: 21,
    contracts: 2,
    strategy: "ICT Model",
  },
  {
    id: "bt-05",
    daysAgo: 18,
    hour: 10,
    ticker: "ES",
    pnl: -180,
    rr: 0.6,
    direction: "Long",
    entry: 5438,
    exit: 5435,
    points: -3,
    contracts: 2,
    strategy: "VWAP Reclaim",
  },
  {
    id: "bt-06",
    daysAgo: 15,
    hour: 9,
    ticker: "NQ",
    pnl: 1120,
    rr: 3.2,
    direction: "Long",
    entry: 19020,
    exit: 19076,
    points: 56,
    contracts: 2,
    strategy: "VWAP Reclaim",
  },
  {
    id: "bt-07",
    daysAgo: 12,
    hour: 13,
    ticker: "ES",
    pnl: 520,
    rr: 2.0,
    direction: "Short",
    entry: 5460,
    exit: 5450,
    points: 10,
    contracts: 2,
    strategy: "Mean Reversion",
  },
  {
    id: "bt-08",
    daysAgo: 9,
    hour: 10,
    ticker: "NQ",
    pnl: 760,
    rr: 2.5,
    direction: "Long",
    entry: 19110,
    exit: 19148,
    points: 38,
    contracts: 2,
    strategy: "Mean Reversion",
  },
  {
    id: "bt-09",
    daysAgo: 6,
    hour: 15,
    ticker: "NQ",
    pnl: -310,
    rr: 0.75,
    direction: "Short",
    entry: 19202,
    exit: 19218,
    points: -16,
    contracts: 2,
    strategy: "Opening Drive",
  },
  {
    id: "bt-10",
    daysAgo: 3,
    hour: 10,
    ticker: "ES",
    pnl: 690,
    rr: 2.2,
    direction: "Long",
    entry: 5472,
    exit: 5483,
    points: 11,
    contracts: 2,
    strategy: "ICT Model",
  },
]

function isoBacktestTime(daysAgo: number, hour: number): string {
  const d = new Date()
  d.setHours(hour, 20, 0, 0)
  d.setDate(d.getDate() - daysAgo)
  return d.toISOString()
}

export function getDemoBacktestTrades(): Record<string, unknown>[] {
  return BACKTEST_SEEDS.map((seed) => {
    const entryTime = isoBacktestTime(seed.daysAgo, seed.hour)
    const exitDate = new Date(entryTime)
    exitDate.setMinutes(exitDate.getMinutes() + 22)
    const tradeDate = entryTime.slice(0, 10)

    return {
      id: seed.id,
      user_id: DEMO_USER_ID,
      ticker: seed.ticker,
      pnl: seed.pnl,
      rr: seed.rr,
      direction: seed.direction,
      entry_price: seed.entry,
      exit_price: seed.exit,
      entry_time: entryTime,
      exit_time: exitDate.toISOString(),
      trade_date: tradeDate,
      date: tradeDate,
      points: seed.points,
      contracts: seed.contracts,
      mode: "backtest",
      account_type: "backtest",
      account_id: null,
      strategy: seed.strategy,
      session: getTradingSession(entryTime),
      created_at: exitDate.toISOString(),
      duration_seconds: 22 * 60,
      duration_text: "22m",
      image_url: demoTradeScreenshotUrl(seed.id, {
        direction: seed.direction,
        pnl: seed.pnl,
      }),
      public_description: null,
      is_public: false,
      notes: `${seed.strategy} backtest — process review saved in journal.`,
      confluences: ["Session VWAP", "Higher-timeframe bias"],
      psychology: "Patient — waited for full trigger confirmation.",
      ai_feedback: null,
    }
  }).sort(
    (a, b) =>
      new Date(String(b.created_at)).getTime() -
      new Date(String(a.created_at)).getTime()
  )
}
