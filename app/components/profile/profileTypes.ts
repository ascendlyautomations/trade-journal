import type { ProfilePostCommentRow } from "@/lib/deleteComment"
import type { ProfileSeoData } from "@/lib/publicSeo"
import type { RoomSharePostFields } from "@/lib/roomSharePost"
import type { TradePointsSource } from "@/lib/resolveTradePoints"
import type { buildTradeTimingPresentation } from "@/lib/tradeTimingDisplay"

export type ProfileHeaderData = ProfileSeoData & {
  bio?: string | null
  avatar_url?: string | null
  trading_style?: string | null
  trading_model?: string | null
  trader_type?: string | null
  primary_market?: string | null
  started_trading?: string | null
}

export type ProfileCardIdentity = Pick<
  ProfileHeaderData,
  "id" | "username" | "avatar_url"
>

export type ProfileTradeRow = TradePointsSource &
  Parameters<typeof buildTradeTimingPresentation>[0] & {
    id: string
    user_id?: string | null
    created_at?: string | null
    image_url?: string | null
    pnl?: unknown
    rr?: unknown
    ticker?: unknown
    account_type?: unknown
    public_description?: unknown
    is_pinned?: boolean | null
    is_public?: boolean | null
    mode?: string | null
    session?: string | null
    [key: string]: unknown
  }

export type ProfileWallPostRow = RoomSharePostFields & {
  id: string
  user_id?: string | null
  created_at?: string | null
  content?: string | null
  image_url?: string | null
  is_pinned?: boolean | null
  [key: string]: unknown
}

export type ProfilePostCardComment = ProfilePostCommentRow & {
  post_id?: string | null
  pinned?: boolean | null
  profiles?: {
    username?: string | null
    avatar_url?: string | null
  } | null
  [key: string]: unknown
}
