import { getDemoLeaderboardTrades } from "@/lib/demo/demoLeaderboard"
import {
  DEMO_USER_ALEX,
  DEMO_USER_ELI,
  DEMO_USER_JORDAN,
  DEMO_USER_MIKE,
  DEMO_USER_SARAH,
} from "@/lib/demo/demoFeed"
import { DEMO_FEED_ITEMS } from "@/lib/demo/demoFeed"
import { DEMO_TRADES } from "@/lib/demo/fixtures"
import {
  SHOWCASE_AVATAR_URL,
  SHOWCASE_USERNAME,
} from "@/lib/guestShowcaseAccount"
import { buildWeeklyTopPerformersPayload } from "@/lib/weeklyTopPerformersBuild"
import type { LeaderboardProfileFields } from "@/lib/leaderboardAggregate"
import type { FeedItem } from "@/app/components/feed/feedPostHelpers"
import { DEMO_USER_ID } from "@/lib/demo/constants"
import { demoTradeScreenshotUrl } from "@/lib/demo/demoAssets"
import type { ReelRow } from "@/lib/reels"

const DEMO_LEADERBOARD_PROFILES: Record<string, LeaderboardProfileFields> = {
  [DEMO_USER_ALEX]: {
    id: DEMO_USER_ALEX,
    username: "alex_futures",
    name: "Alex M.",
    avatar_url: null,
  },
  [DEMO_USER_SARAH]: {
    id: DEMO_USER_SARAH,
    username: "sarah_scalps",
    name: "Sarah K.",
    avatar_url: null,
  },
  [DEMO_USER_JORDAN]: {
    id: DEMO_USER_JORDAN,
    username: "jk_futures",
    name: "Jordan K.",
    avatar_url: null,
  },
  [DEMO_USER_MIKE]: {
    id: DEMO_USER_MIKE,
    username: "mike_trades",
    name: "Mike R.",
    avatar_url: null,
  },
  [DEMO_USER_ELI]: {
    id: DEMO_USER_ELI,
    username: "eli_edges",
    name: "Eli T.",
    avatar_url: null,
  },
}

export function getLandingDemoTrades() {
  return DEMO_TRADES
}

/** NQ showcase trade for journal → Feed marketing (dt-24). */
export function getMarketingJournalShowcaseTrades() {
  const trade = DEMO_TRADES.find((row) => row.id === "dt-24") ?? DEMO_TRADES[0]
  return trade ? [trade] : []
}

/** Same clip as demo feed post `demo-post-1` / trade `dt-24`. */
export function getMarketingJournalShowcaseReel(): ReelRow {
  const trade = DEMO_TRADES.find((row) => row.id === "dt-24")
  const chartPoster =
    (typeof trade?.image_url === "string" && trade.image_url.trim()) ||
    demoTradeScreenshotUrl("dt-24", { direction: "Long", pnl: 1050 })
  const created =
    (typeof trade?.created_at === "string" && trade.created_at) ||
    "2026-11-03T15:25:00.000Z"
  return {
    id: "demo-reel-1",
    user_id: DEMO_USER_ID,
    caption: null,
    video_url:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    thumbnail_url: chartPoster,
    duration_seconds: 42,
    trade_id: "dt-24",
    visibility: "public",
    kind: null,
    created_at: created,
    updated_at: created,
  }
}

function marketingTradeJoinFromDemo(trade: (typeof DEMO_TRADES)[number]) {
  return {
    user_id: trade.user_id,
    created_at: trade.created_at,
    ticker: trade.ticker,
    direction: trade.direction,
    account_type: "prop",
    points: trade.points,
    entry_time: trade.entry_time,
    exit_time: trade.exit_time,
    entry_price: trade.entry_price,
    exit_price: trade.exit_price,
    trade_date: trade.trade_date,
    duration_seconds: trade.duration_seconds,
    duration_text: trade.duration_text,
    public_description: trade.public_description,
    image_url: trade.image_url,
    reels: getMarketingJournalShowcaseReel(),
  }
}

/** Feed post paired with journal showcase — same NQ trade + Explore showcase profile. */
export function getMarketingJournalFeedPost(): FeedItem | null {
  const trade = DEMO_TRADES.find((row) => row.id === "dt-24")
  const base = DEMO_FEED_ITEMS.find((item) => item.id === "demo-post-1")
  if (!trade || !base) return base ?? null

  return {
    ...base,
    pnl: trade.pnl,
    rr: trade.rr,
    image_url: trade.image_url,
    created_at: String(trade.exit_time ?? trade.created_at),
    profiles: {
      username: SHOWCASE_USERNAME,
      avatar_url: SHOWCASE_AVATAR_URL,
    },
    trades: marketingTradeJoinFromDemo(trade),
  }
}

export function getLandingDemoWeeklyPerformers() {
  return buildWeeklyTopPerformersPayload(
    getDemoLeaderboardTrades(),
    DEMO_LEADERBOARD_PROFILES
  )
}
