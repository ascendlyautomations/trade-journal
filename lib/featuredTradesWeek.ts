import type { FeedItem } from "@/app/components/feed/feedPostHelpers"

export type FeaturedTradesWeekResponse = {
  bestPnlPost: FeedItem | null
  highestRrPost: FeedItem | null
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
      return { bestPnlPost: null, highestRrPost: null }
    }
    const data = (await res.json()) as FeaturedTradesWeekResponse
    return {
      bestPnlPost: data.bestPnlPost ?? null,
      highestRrPost: data.highestRrPost ?? null,
    }
  } catch (error) {
    console.error("[featured-trades] fetch error", error)
    return { bestPnlPost: null, highestRrPost: null }
  }
}
