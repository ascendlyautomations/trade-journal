import { DEMO_USER_ID } from "./constants"
import { demoAvatarUrl, demoReelThumbnailUrl } from "./demoAvatars"
import { demoTradeScreenshotUrl } from "./demoAssets"
import { getTradingSession } from "@/lib/formatDate"

export const DEMO_PROFILE = {
  id: DEMO_USER_ID,
  username: "john_trades",
  name: "John Jones",
  bio: "Futures trader focused on NQ & ES. Sharing the journey — wins, losses, and lessons.",
  avatar_url: demoAvatarUrl(DEMO_USER_ID),
  is_pro: true,
  subscription_status: "active",
  trading_style: "Day Trading",
  trading_model: null as string | null,
  trader_type: "Futures",
  primary_market: "US Indices",
  started_trading: "2021",
  is_private: false,
  referral_code: "MAYADEMO",
  referral_count: 12,
  is_banned: false,
  banned_reason: null as string | null,
  is_beta_tester: false,
  onboarding_completed: true,
  has_seen_getting_started_intro: true,
  has_seen_onboarding_complete_popup: true,
  max_drawdown_limit: 5000,
  has_email_password: false,
  cancel_at_period_end: false,
}

export const DEMO_ACCOUNTS = [
  {
    id: "demo-account-eval",
    user_id: DEMO_USER_ID,
    name: "Apex 150K Eval",
    account_size: "150000",
    account_number: "APEX-88421",
    mode: "eval",
    category: "Prop Firm",
    is_active: true,
    consistency: 40,
    max_drawdown: 4500,
    daily_drawdown: 2500,
    profit_target: 9000,
    winning_days: 5,
    winning_day_threshold: 150,
    payout_drawdown_behavior: null,
    remember_payout_drawdown_behavior: false,
  },
  {
    id: "demo-account-funded-prop",
    user_id: DEMO_USER_ID,
    name: "Apex 150K Funded",
    account_size: "150000",
    account_number: "APEX-F8821",
    mode: "funded",
    category: "Prop Firm",
    is_active: true,
    consistency: 40,
    max_drawdown: 4500,
    daily_drawdown: 2500,
    profit_target: null,
    winning_days: 8,
    winning_day_threshold: 150,
    payout_drawdown_behavior: "balance_based",
    remember_payout_drawdown_behavior: true,
  },
  {
    id: "demo-account-funded",
    user_id: DEMO_USER_ID,
    name: "Personal Futures",
    account_size: "50000",
    account_number: "PERS-22018",
    mode: "live",
    category: "personal",
    is_active: true,
  },
] as const

export const DEMO_AI_FEEDBACK = `## Summary
This was a high-quality opening-drive long with disciplined risk and a strong reward relative to your typical NQ trades. The result aligns with your best-performing session and setup patterns.

## Strengths
- RR exceeded your historical average, showing intentional risk placement rather than outcome-chasing.
- Entry followed a clear liquidity sweep and break-of-structure sequence noted in your journal.
- Position sizing stayed within normal eval risk parameters for a trade of this size.

## Areas for Improvement
- Entry was slightly late after the BOS confirmation candle — a few ticks of slippage reduced optimal RR.
- Partial profit could have been more aggressive when momentum stalled at the first extension target.

## Behavior Observed
You waited for confirmation instead of anticipating the move, which matches your strongest recent NY session behavior. Patience and process were consistent with your recent winning streak.

## Recommendations
1. Set alerts at the trigger level to tighten entry timing on similar opening-drive setups.
2. Scale 50% at the first extension when 5m momentum slows, then manage the remainder to plan.
3. Repeat this workflow on comparable liquidity-sweep contexts during the NY open.

## Questions That Could Improve Future Analysis
What was your planned invalidation level before entry — did price ever threaten that level after you were in?`

type TradeSeed = {
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
  mode: string
  accountId: string
}

const TRADE_SEEDS: TradeSeed[] = [
  { id: "dt-01", daysAgo: 58, hour: 10, ticker: "NQ", pnl: 840, rr: 2.1, direction: "Long", entry: 17820, exit: 17862, points: 42, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-02", daysAgo: 56, hour: 9, ticker: "ES", pnl: -320, rr: 0.7, direction: "Short", entry: 5288, exit: 5294, points: -6, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-03", daysAgo: 54, hour: 14, ticker: "NQ", pnl: 1260, rr: 3.2, direction: "Long", entry: 17910, exit: 17973, points: 63, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-04", daysAgo: 51, hour: 11, ticker: "CL", pnl: 410, rr: 1.8, direction: "Long", entry: 71.2, exit: 71.65, points: 0.45, contracts: 1, mode: "live", accountId: "demo-account-funded" },
  { id: "dt-05", daysAgo: 49, hour: 10, ticker: "NQ", pnl: -540, rr: 0.9, direction: "Short", entry: 18005, exit: 18032, points: -27, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-06", daysAgo: 47, hour: 15, ticker: "ES", pnl: 620, rr: 2.4, direction: "Long", entry: 5312, exit: 5324, points: 12, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-07", daysAgo: 44, hour: 9, ticker: "NQ", pnl: 980, rr: 2.8, direction: "Long", entry: 18120, exit: 18169, points: 49, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-08", daysAgo: 42, hour: 13, ticker: "ES", pnl: -280, rr: 0.6, direction: "Long", entry: 5338, exit: 5332, points: -6, contracts: 2, mode: "live", accountId: "demo-account-funded" },
  { id: "dt-09", daysAgo: 39, hour: 10, ticker: "NQ", pnl: 1540, rr: 3.5, direction: "Short", entry: 18240, exit: 18163, points: 77, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-10", daysAgo: 37, hour: 11, ticker: "AAPL", pnl: 220, rr: 1.5, direction: "Long", entry: 198.4, exit: 200.1, points: 1.7, contracts: 100, mode: "live", accountId: "demo-account-funded" },
  { id: "dt-11", daysAgo: 35, hour: 9, ticker: "NQ", pnl: -410, rr: 0.8, direction: "Long", entry: 18302, exit: 18281, points: -21, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-12", daysAgo: 33, hour: 14, ticker: "ES", pnl: 740, rr: 2.2, direction: "Short", entry: 5368, exit: 5356, points: 12, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-13", daysAgo: 30, hour: 10, ticker: "NQ", pnl: 1120, rr: 2.9, direction: "Long", entry: 18410, exit: 18466, points: 56, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-14", daysAgo: 28, hour: 15, ticker: "CL", pnl: -190, rr: 0.5, direction: "Short", entry: 72.8, exit: 73.05, points: -0.25, contracts: 1, mode: "live", accountId: "demo-account-funded" },
  { id: "dt-15", daysAgo: 25, hour: 9, ticker: "ES", pnl: 510, rr: 1.9, direction: "Long", entry: 5382, exit: 5392, points: 10, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-16", daysAgo: 22, hour: 11, ticker: "NQ", pnl: -680, rr: 0.7, direction: "Short", entry: 18520, exit: 18554, points: -34, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-17", daysAgo: 20, hour: 10, ticker: "NQ", pnl: 1380, rr: 3.1, direction: "Long", entry: 18602, exit: 18671, points: 69, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-18", daysAgo: 17, hour: 13, ticker: "ES", pnl: 390, rr: 1.7, direction: "Short", entry: 5410, exit: 5402, points: 8, contracts: 2, mode: "live", accountId: "demo-account-funded" },
  { id: "dt-19", daysAgo: 14, hour: 9, ticker: "NQ", pnl: 920, rr: 2.5, direction: "Long", entry: 18740, exit: 18786, points: 46, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-20", daysAgo: 11, hour: 10, ticker: "ES", pnl: -350, rr: 0.75, direction: "Long", entry: 5428, exit: 5421, points: -7, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-21", daysAgo: 8, hour: 14, ticker: "NQ", pnl: 1640, rr: 3.8, direction: "Short", entry: 18880, exit: 18798, points: 82, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-22", daysAgo: 5, hour: 10, ticker: "NQ", pnl: 780, rr: 2.3, direction: "Long", entry: 18920, exit: 18959, points: 39, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-23", daysAgo: 2, hour: 9, ticker: "ES", pnl: 450, rr: 1.8, direction: "Long", entry: 5448, exit: 5457, points: 9, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
  { id: "dt-24", daysAgo: 0, hour: 10, ticker: "NQ", pnl: 1050, rr: 2.7, direction: "Long", entry: 19010, exit: 19062, points: 52, contracts: 2, mode: "eval", accountId: "demo-account-eval" },
]

function isoTradeTime(daysAgo: number, hour: number): string {
  const d = new Date()
  d.setHours(hour, 15, 0, 0)
  d.setDate(d.getDate() - daysAgo)
  return d.toISOString()
}

export const DEMO_TRADES = TRADE_SEEDS.map((seed) => {
  const entryTime = isoTradeTime(seed.daysAgo, seed.hour)
  const exitDate = new Date(entryTime)
  exitDate.setMinutes(exitDate.getMinutes() + 18)
  const account = DEMO_ACCOUNTS.find((a) => a.id === seed.accountId)
  const tradeDate = entryTime.slice(0, 10)
  const base = {
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
    mode: seed.mode,
    account_type: account?.category ?? "prop",
    account_id: seed.accountId,
    session: getTradingSession(entryTime),
    created_at: exitDate.toISOString(),
    duration_seconds: 18 * 60,
    duration_text: "18m",
    image_url: demoTradeScreenshotUrl(seed.id, {
      direction: seed.direction,
      pnl: seed.pnl,
    }),
    public_description: null,
    is_public: false,
    notes: null as string | null,
    confluences: null as string[] | null,
    mistakes: null as string | null,
    psychology: null as string | null,
    ai_feedback: null as string | null,
  }
  if (seed.id === "dt-24") {
    return {
      ...base,
      is_public: true,
      public_description:
        "Clean opening drive long — waited for liquidity sweep, entered on 1m BOS.",
      notes:
        "Opening drive long after liquidity sweep at overnight low. Entered on 1m BOS with stop below sweep.",
      confluences: ["HTF bullish structure", "VWAP reclaim", "Opening range high break"],
      psychology: "Calm and patient — waited for full confirmation before entry.",
      ai_feedback: DEMO_AI_FEEDBACK,
    }
  }
  return base
}).sort(
  (a, b) =>
    new Date(b.exit_time ?? b.created_at).getTime() -
    new Date(a.exit_time ?? a.created_at).getTime()
)

export const DEMO_FEED_POSTS = [
  {
    id: "demo-post-1",
    user_id: DEMO_USER_ID,
    pnl: 1050,
    created_at: DEMO_TRADES[0].created_at,
    image_url: demoTradeScreenshotUrl("dt-24", { direction: "Long", pnl: 1050 }),
    profiles: { username: DEMO_PROFILE.username, avatar_url: demoAvatarUrl(DEMO_USER_ID) },
    trades: {
      ticker: "NQ",
      direction: "Long",
      rr: 2.7,
      account_type: "prop",
      public_description:
        "Clean opening drive long — waited for liquidity sweep, entered on 1m BOS. Took partials at VWAP extension.",
    },
  },
  {
    id: "demo-post-2",
    user_id: "demo-user-2",
    pnl: 720,
    created_at: isoTradeTime(3, 11),
    image_url: demoTradeScreenshotUrl("demo-post-2", { direction: "Short", pnl: 720 }),
    profiles: { username: "alex_futures", avatar_url: demoAvatarUrl("demo-user-alex") },
    trades: {
      ticker: "ES",
      direction: "Short",
      rr: 2.1,
      account_type: "prop",
      public_description: "Reversal off overnight high. Shared the full breakdown in Trade Rooms earlier.",
    },
  },
  {
    id: "demo-post-3",
    user_id: "demo-user-3",
    pnl: -280,
    created_at: isoTradeTime(6, 14),
    image_url: demoTradeScreenshotUrl("demo-post-3", { direction: "Long", pnl: -280 }),
    profiles: { username: "jordan_scalps", avatar_url: demoAvatarUrl("demo-user-jordan") },
    trades: {
      ticker: "NQ",
      direction: "Long",
      rr: 0.6,
      account_type: "personal",
      public_description: "Took a loss today — rushed entry before confirmation. Journal notes saved for review.",
    },
  },
] as const

export const DEMO_ACHIEVEMENTS = [
  { id: "a1", title: "First Green Week", description: "5 consecutive profitable days", icon: "🏆", earned: "Mar 2026" },
  { id: "a2", title: "100 Trades Logged", description: "Consistency builds edge", icon: "📊", earned: "Feb 2026" },
  { id: "a3", title: "Prop Firm Passed", description: "Apex 150K evaluation cleared", icon: "🎯", earned: "Jan 2026" },
  { id: "a4", title: "Community Helper", description: "50 helpful comments", icon: "💬", earned: "Dec 2025" },
  { id: "a5", title: "Clip Creator", description: "10 trade breakdown clips", icon: "🎬", earned: "Nov 2025" },
  { id: "a6", title: "Risk Discipline", description: "30 days within daily loss limit", icon: "🛡️", earned: "Oct 2025" },
] as const

export const DEMO_AI_ANALYSIS = {
  tradeTicker: "NQ",
  summary:
    "Strong execution on trend continuation setup. Entry aligned with higher-timeframe bullish structure and session VWAP support.",
  strengths: [
    "Waited for liquidity sweep before entry",
    "Risk-to-reward exceeded 2:1 plan",
    "Held through minor pullback without moving stop",
  ],
  improvements: [
    "Consider scaling out earlier when RSI reached overbought on 5m",
    "Entry was 2 ticks late — set alert at trigger level",
  ],
  patterns: ["Morning trend continuation", "VWAP reclaim long", "Opening range breakout"],
  markdown: DEMO_AI_FEEDBACK,
}

export const DEMO_PAYOUT_CYCLES: Record<
  string,
  Array<{
    id: string
    account_id: string
    started_at: string
    ended_at: string | null
    cycle_start_balance: number
    payout_amount: number | null
    note: string | null
    balance_before_payout: number | null
    balance_after_payout: number | null
    drawdown_behavior: "balance_based" | "fixed" | null
    drawdown_floor_after_payout: number | null
    cycle_number: number | null
  }>
> = {
  "demo-account-funded-prop": [
    {
      id: "demo-payout-cycle-1",
      account_id: "demo-account-funded-prop",
      started_at: isoTradeTime(45, 10),
      ended_at: isoTradeTime(30, 15),
      cycle_start_balance: 150000,
      payout_amount: 2400,
      note: "First payout",
      balance_before_payout: 154800,
      balance_after_payout: 152400,
      drawdown_behavior: "balance_based",
      drawdown_floor_after_payout: 147600,
      cycle_number: 1,
    },
  ],
}

export const DEMO_PROP_FIRM = {
  accountName: "Apex 150K Eval",
  status: "ACTIVE" as const,
  profitTarget: 9000,
  profitProgress: 6240,
  maxDrawdown: 4500,
  drawdownUsed: 1820,
  dailyDrawdown: 2500,
  winningDays: 4,
  winningDaysRequired: 5,
  consistency: 38,
  consistencyLimit: 40,
}

export const DEMO_TRADE_ROOMS = [
  { id: "room-1", name: "NQ Morning Traders", members: 24, active: true, preview: "Live commentary during US open…" },
  { id: "room-2", name: "Prop Firm Journey", members: 18, active: false, preview: "Sharing eval progress and rule tracking tips" },
  { id: "room-3", name: "Trade Review Lounge", members: 31, active: true, preview: "Post your setups for same-day feedback" },
] as const

export const DEMO_FOLLOWERS = { followers: 1284, following: 186 }

export const DEMO_REELS = [
  {
    id: "reel-1",
    title: "NQ Opening Drive Breakdown",
    views: 2400,
    duration: "0:42",
    thumbnail_url: demoReelThumbnailUrl("reel-1"),
    caption: "NQ Opening Drive Breakdown — liquidity sweep + BOS entry",
  },
  {
    id: "reel-2",
    title: "How I Passed My Eval",
    views: 5100,
    duration: "1:15",
    thumbnail_url: demoReelThumbnailUrl("reel-2"),
    caption: "How I Passed My Eval — rule tracking workflow",
  },
  {
    id: "reel-3",
    title: "3 Mistakes From Last Week",
    views: 1800,
    duration: "0:58",
    thumbnail_url: demoReelThumbnailUrl("reel-3"),
    caption: "3 Mistakes From Last Week — journal review",
  },
] as const
