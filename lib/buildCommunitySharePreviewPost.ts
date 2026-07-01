/** Build a feed-shaped post object from Input Trade form state (no DB writes). */

import { resolveFeedTradeAccountType } from "./feedAccountType.ts"
import { resolveTradePoints } from "./resolveTradePoints"

export type CommunitySharePreviewInput = {
  userId: string
  username: string
  avatarUrl: string | null
  pnl: string | number
  rr: string | number
  points: string | number
  ticker: string
  direction: string
  accountMode?: string | null
  accountType?: string | null
  lockedAccountType?: string | null
  isPro?: boolean
  publicDescription: string
  imageUrl: string | null
  entryTime?: string | null
  exitTime?: string | null
  entryPrice?: string | number | null
  exitPrice?: string | number | null
  tradeDate?: string | null
}

function parseNumericField(value: string | number): number | null {
  if (value === "" || value === null || value === undefined) return null
  const n = Number(String(value).replace(/,/g, ""))
  return Number.isFinite(n) ? n : null
}

export function buildCommunitySharePreviewPost(
  input: CommunitySharePreviewInput
): Record<string, unknown> {
  const pnl = parseNumericField(input.pnl) ?? 0
  const rr = parseNumericField(input.rr)
  const entryPrice = parseNumericField(input.entryPrice ?? null)
  const exitPrice = parseNumericField(input.exitPrice ?? null)
  const points = resolveTradePoints({
    points: parseNumericField(input.points),
    entry_price: entryPrice,
    exit_price: exitPrice,
    direction: input.direction,
  })
  const accountType = resolveFeedTradeAccountType({
    mode: input.accountMode,
    accountType: input.accountType,
    lockedAccountType: input.lockedAccountType,
    isPro: input.isPro,
  })

  return {
    id: "community-preview",
    user_id: input.userId,
    trade_id: "community-preview",
    created_at: new Date().toISOString(),
    pnl,
    rr,
    image_url: input.imageUrl,
    profiles: {
      username: input.username.trim() || "User",
      avatar_url: input.avatarUrl,
    },
    trades: {
      created_at: new Date().toISOString(),
      public_description: input.publicDescription,
      user_id: input.userId,
      ticker: input.ticker.trim() || "—",
      direction: input.direction || "—",
      account_type: accountType,
      points,
      entry_time: input.entryTime ?? null,
      exit_time: input.exitTime ?? null,
      entry_price: entryPrice,
      exit_price: exitPrice,
      trade_date: input.tradeDate ?? null,
    },
  }
}
