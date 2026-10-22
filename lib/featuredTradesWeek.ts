import type { FeedItem } from "@/app/components/feed/feedPostHelpers"

export type FeaturedTradesWeekResponse = {
  bestPnlPost: FeedItem | null
  highestRrPost: FeedItem | null
  sectionTitle: string
  sectionLead: string
  isHistoricalPeriod: boolean
}

export {
  getFeaturedWeekStartIso,
  isPublicDiscoverableTradeRow,
  pickBestPnlPost,
  pickHighestRrPost,
} from "./featuredTradesWeekLogic"

export async function fetchFeaturedTradesWeek(): Promise<FeaturedTradesWeekResponse> {
  try {
    const res = await fetch("/api/featured-trades", {
      next: { revalidate: 600 },
    })
    if (!res.ok) {
      console.error("[featured-trades] fetch failed", res.status, res.statusText)
      return {
        bestPnlPost: null,
        highestRrPost: null,
        sectionTitle: "Featured Trades of the Week",
        sectionLead:
          "Discover some of the community's best trades from this calendar week.",
        isHistoricalPeriod: false,
      }
    }
    const data = (await res.json()) as FeaturedTradesWeekResponse
    return {
      bestPnlPost: data.bestPnlPost ?? null,
      highestRrPost: data.highestRrPost ?? null,
      sectionTitle:
        data.sectionTitle ?? "Featured Trades of the Week",
      sectionLead:
        data.sectionLead ??
        "Discover some of the community's best trades from this calendar week.",
      isHistoricalPeriod: data.isHistoricalPeriod ?? false,
    }
  } catch (error) {
    console.error("[featured-trades] fetch error", error)
    return {
      bestPnlPost: null,
      highestRrPost: null,
      sectionTitle: "Featured Trades of the Week",
      sectionLead:
        "Discover some of the community's best trades from this calendar week.",
      isHistoricalPeriod: false,
    }
  }
}
