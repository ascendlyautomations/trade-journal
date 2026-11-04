import { normalizeTradeFeedItem } from "@/app/components/feed/feedPostHelpers"
import type { FeaturedTradesWeekResponse } from "@/lib/featuredTradesWeek"
import {
  featuredTradesPeriodHeading,
  pickFeaturedTradePair,
  resolveFeaturedTradesPeriod,
} from "@/lib/featuredTradesPeriodFallback.ts"
import { fetchFeaturedPostCandidates } from "@/lib/featuredTradesCandidates.ts"

const EMPTY_HEADING = {
  sectionTitle: "Featured Trades of the Week",
  sectionLead:
    "Public trades logged on TradeTraxs, shared from the journal with real P&L, not staged marketing picks.",
}

/** Server-side featured trades fetch — shared by homepage cache and API route. */
export async function fetchFeaturedTradesWeekServer(): Promise<FeaturedTradesWeekResponse> {
  const rows = await fetchFeaturedPostCandidates()
  const period = resolveFeaturedTradesPeriod(rows, rows)

  if (!period) {
    return {
      bestPnlPost: null,
      highestRrPost: null,
      ...EMPTY_HEADING,
      isHistoricalPeriod: false,
    }
  }

  const { bestPnl: bestPnlRow, highestRr: highestRrRow } = pickFeaturedTradePair(
    rows,
    period.start,
    period.end
  )
  const heading = featuredTradesPeriodHeading(period)

  return {
    bestPnlPost: bestPnlRow
      ? normalizeTradeFeedItem(bestPnlRow as Record<string, unknown>)
      : null,
    highestRrPost: highestRrRow
      ? normalizeTradeFeedItem(highestRrRow as Record<string, unknown>)
      : null,
    sectionTitle: heading.sectionTitle,
    sectionLead: heading.sectionLead,
    isHistoricalPeriod: period.kind !== "current_week",
  }
}
