import type { TradeForLeaderboard } from "@/lib/leaderboardChart"
import { DEMO_USER_ID } from "./constants"
import { DEMO_TRADES } from "./fixtures"
import {
  DEMO_USER_ALEX,
  DEMO_USER_ELI,
  DEMO_USER_JORDAN,
  DEMO_USER_MIKE,
  DEMO_USER_SARAH,
} from "./demoFeed"

function isoDaysAgo(daysAgo: number, hour = 10): string {
  const d = new Date()
  d.setHours(hour, 30, 0, 0)
  d.setDate(d.getDate() - daysAgo)
  return d.toISOString()
}

const DEMO_LEADERBOARD_SYNTHETIC: TradeForLeaderboard[] = [
  { user_id: DEMO_USER_ALEX, pnl: 840, rr: 2.4, created_at: isoDaysAgo(1), account_type: "prop", mode: "eval" },
  { user_id: DEMO_USER_ALEX, pnl: 620, rr: 2.1, created_at: isoDaysAgo(2), account_type: "prop", mode: "eval" },
  { user_id: DEMO_USER_SARAH, pnl: 1180, rr: 3.0, created_at: isoDaysAgo(1), account_type: "prop", mode: "eval" },
  { user_id: DEMO_USER_SARAH, pnl: 890, rr: 2.4, created_at: isoDaysAgo(3), account_type: "prop", mode: "eval" },
  { user_id: DEMO_USER_JORDAN, pnl: -280, rr: 0.6, created_at: isoDaysAgo(2), account_type: "personal", mode: "live" },
  { user_id: DEMO_USER_JORDAN, pnl: 540, rr: 1.9, created_at: isoDaysAgo(4), account_type: "prop", mode: "eval" },
  { user_id: DEMO_USER_MIKE, pnl: 720, rr: 2.1, created_at: isoDaysAgo(2), account_type: "prop", mode: "eval" },
  { user_id: DEMO_USER_ELI, pnl: 1180, rr: 3.0, created_at: isoDaysAgo(5), account_type: "prop", mode: "eval" },
  { user_id: DEMO_USER_ELI, pnl: 450, rr: 1.8, created_at: isoDaysAgo(6), account_type: "prop", mode: "eval" },
]

export function getDemoLeaderboardTrades(): TradeForLeaderboard[] {
  const fromMaya = DEMO_TRADES.filter((t) => t.is_public).map((t) => ({
    user_id: DEMO_USER_ID,
    pnl: Number(t.pnl) || 0,
    rr: Number(t.rr) || 0,
    created_at: String(t.created_at),
    account_type: String(t.account_type ?? "prop"),
    mode: String(t.mode ?? "eval"),
  }))

  return [...fromMaya, ...DEMO_LEADERBOARD_SYNTHETIC].sort(
    (a, b) =>
      new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  )
}
