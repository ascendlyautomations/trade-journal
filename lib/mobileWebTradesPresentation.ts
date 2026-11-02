import type { TradesPageListItem } from "./copyTradePresentation.ts"
import { DASHBOARD_TF_LABEL_FROM_VALUE } from "./dashboardTimeframeLabels.ts"
import { resolveTradePoints, type TradePointsSource } from "./resolveTradePoints.ts"
import {
  sortTradesForDisplay,
  TRADES_SORT_OPTIONS,
  type TradesSortKey,
} from "./tradesSort.ts"

/** Native journal thumbnail: 96pt wide, height from image, 36–120pt. */
export const MOBILE_WEB_TRADE_THUMB_WIDTH_PX = 96
export const MOBILE_WEB_TRADE_THUMB_MIN_HEIGHT_PX = 36
export const MOBILE_WEB_TRADE_THUMB_MAX_HEIGHT_PX = 120

/** Size the 96px-wide thumb to the image aspect, clamped like ProfileCompactMediaThumbnail. */
export function mobileWebTradeThumbHeightPx(
  naturalWidth: number,
  naturalHeight: number
): number {
  if (!(naturalWidth > 0) || !(naturalHeight > 0)) {
    return MOBILE_WEB_TRADE_THUMB_WIDTH_PX
  }
  const height = MOBILE_WEB_TRADE_THUMB_WIDTH_PX / (naturalWidth / naturalHeight)
  return Math.min(
    MOBILE_WEB_TRADE_THUMB_MAX_HEIGHT_PX,
    Math.max(MOBILE_WEB_TRADE_THUMB_MIN_HEIGHT_PX, Math.round(height))
  )
}

export function hasMobileWebTradeScreenshot(
  url: string | null | undefined
): boolean {
  return Boolean(url && String(url).trim())
}

function compactNumber(value: number): string {
  return value.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

/** Native `journalRRText` — `1:2.9`. Omit when missing. */
export function mobileWebJournalRrLabel(rr: unknown): string | null {
  if (rr === null || rr === undefined || String(rr).trim() === "") return null
  const number = Number(rr)
  if (!Number.isFinite(number)) return null
  return `1:${compactNumber(number)}`
}

/** Native `pointsText`. Omit when missing. */
export function mobileWebJournalPointsLabel(
  trade: TradePointsSource | null | undefined
): string | null {
  const resolved = resolveTradePoints(trade)
  if (resolved === null) return null
  return compactNumber(resolved)
}

export type MobileWebTradesChipId =
  | "account"
  | "mode"
  | "timeframe"
  | "result"
  | "public"
  | "sort"
  | "search"

export type MobileWebTradesChip = {
  id: MobileWebTradesChipId
  title: string
}

const MODE_LABEL: Record<string, string> = {
  live: "Live",
  funded: "Funded",
  eval: "Eval",
}

const RESULT_LABEL: Record<string, string> = {
  wins: "Wins",
  losses: "Losses",
}

export function tradeMatchesMobileWebSearch(
  trade: {
    ticker?: unknown
    notes?: unknown
    public_description?: unknown
    session?: unknown
  },
  query: string
): boolean {
  const q = query.trim().toLowerCase()
  if (!q) return true
  const fields = [
    trade.ticker,
    trade.notes,
    trade.public_description,
    trade.session,
  ]
  return fields.some((field) => String(field ?? "").toLowerCase().includes(q))
}

export function tradeListItemMatchesMobileWebSearch(
  item: TradesPageListItem,
  query: string
): boolean {
  if (!query.trim()) return true
  if (item.kind === "single") {
    return tradeMatchesMobileWebSearch(item.trade, query)
  }
  return item.members.some((member) =>
    tradeMatchesMobileWebSearch(member, query)
  )
}

function listItemSortFields(item: TradesPageListItem): {
  created_at?: string | null
  pnl?: number | null
  rr?: unknown
} {
  const trade = (item.kind === "copyGroup" ? item.representative : item.trade) as {
    created_at?: unknown
    pnl?: unknown
    rr?: unknown
  }
  const createdAt =
    typeof trade.created_at === "string" || trade.created_at == null
      ? (trade.created_at ?? null)
      : String(trade.created_at)
  const pnl = Number(trade.pnl)
  return {
    created_at: createdAt,
    pnl: Number.isFinite(pnl) ? pnl : null,
    rr: trade.rr,
  }
}

export function sortTradeListItemsForMobileWeb(
  items: readonly TradesPageListItem[],
  sortBy: TradesSortKey
): TradesPageListItem[] {
  const decorated = items.map((item, index) => ({
    ...listItemSortFields(item),
    index,
  }))
  return sortTradesForDisplay(decorated, sortBy).map(
    (row) => items[row.index] as TradesPageListItem
  )
}

export function buildMobileWebTradesChips(input: {
  search: string
  accountFilter: string
  accountLabel?: string
  accountTypeFilter: string
  timeframe: string
  selectedDate: string
  customRangeStart?: string
  customRangeEnd?: string
  resultFilter: "all" | "wins" | "losses"
  showPublicOnly: boolean
  sortBy: TradesSortKey
}): MobileWebTradesChip[] {
  const chips: MobileWebTradesChip[] = []
  const search = input.search.trim()
  if (search) chips.push({ id: "search", title: `“${search}”` })

  if (input.accountFilter && input.accountFilter !== "all") {
    chips.push({
      id: "account",
      title: input.accountLabel?.trim() || "Account",
    })
  }

  if (input.accountTypeFilter && input.accountTypeFilter !== "all") {
    chips.push({
      id: "mode",
      title: MODE_LABEL[input.accountTypeFilter] ?? input.accountTypeFilter,
    })
  }

  const timeframeTitle = mobileWebTimeframeChipTitle(input)
  if (timeframeTitle) chips.push({ id: "timeframe", title: timeframeTitle })

  if (input.resultFilter !== "all") {
    chips.push({
      id: "result",
      title: RESULT_LABEL[input.resultFilter] ?? input.resultFilter,
    })
  }

  if (input.showPublicOnly) chips.push({ id: "public", title: "Public" })

  if (input.sortBy !== "newest") {
    const sortLabel =
      TRADES_SORT_OPTIONS.find((option) => option.key === input.sortBy)
        ?.label ?? input.sortBy
    chips.push({ id: "sort", title: sortLabel })
  }

  return chips
}

function mobileWebTimeframeChipTitle(input: {
  timeframe: string
  selectedDate: string
  customRangeStart?: string
  customRangeEnd?: string
}): string | null {
  if (input.selectedDate.trim()) return input.selectedDate
  if (input.timeframe === "custom") {
    if (input.customRangeStart && input.customRangeEnd) {
      return `${input.customRangeStart} – ${input.customRangeEnd}`
    }
    return "Custom"
  }
  if (!input.timeframe || input.timeframe === "all") return null
  return DASHBOARD_TF_LABEL_FROM_VALUE[input.timeframe] ?? input.timeframe
}
