import { normalizeTradeFeedItem } from "@/app/components/feed/feedPostHelpers"
import type { FeaturedTradesWeekResponse } from "@/lib/featuredTradesWeek"
import {
  featuredTradesPeriodHeading,
  resolveFeaturedTradesPeriod,
} from "@/lib/featuredTradesPeriodFallback.ts"
import {
  pickBestPnlPost,
  pickHighestRrPost,
} from "@/lib/featuredTradesWeekLogic"
import { fetchFeaturedPostCandidates } from "@/lib/featuredTradesCandidates.ts"

function rowsInRange<T extends { created_at?: string }>(
  rows: readonly T[],
  start: Date,
  end: Date
): T[] {
  const startMs = start.getTime()
  const endMs = end.getTime()
  return rows.filter((row) => {
    if (!row.created_at) return false
    const ms = new Date(row.created_at).getTime()
    return ms >= startMs && ms <= endMs
  })
}

const EMPTY_HEADING = {
  sectionTitle: "Featured Trades of the Week",
  sectionLead:
    "Discover some of the community's best trades from this calendar week.",
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

  const inPeriod = rowsInRange(rows, period.start, period.end)
  const bestPnlRow = pickBestPnlPost(inPeriod)
  const highestRrRow = pickHighestRrPost(inPeriod)
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
