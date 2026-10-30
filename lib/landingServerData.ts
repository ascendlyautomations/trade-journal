import { unstable_cache } from "next/cache"
import { fetchFeaturedTradesWeekServer } from "@/lib/featuredTradesWeekServer"
import { loadPublicUserReviews } from "@/lib/landingPublicReviews"
import { fetchWeeklyTopPerformersServer } from "@/lib/weeklyTopPerformersServer"
import {
  LANDING_FEATURED_TRADES_REVALIDATE_SECONDS,
  LANDING_REVIEWS_REVALIDATE_SECONDS,
  LANDING_WEEKLY_TOP_TRADERS_REVALIDATE_SECONDS,
} from "@/lib/marketingCacheConfig"

export {
  LANDING_FEATURED_TRADES_REVALIDATE_SECONDS,
  LANDING_REVIEWS_REVALIDATE_SECONDS,
} from "@/lib/marketingCacheConfig"
export { loadPublicUserReviews } from "@/lib/landingPublicReviews"

export const getCachedLandingReviews = unstable_cache(
  loadPublicUserReviews,
  ["landing-public-reviews"],
  {
    revalidate: LANDING_REVIEWS_REVALIDATE_SECONDS,
    tags: ["landing-reviews"],
  }
)

export const getCachedLandingFeaturedTrades = unstable_cache(
  fetchFeaturedTradesWeekServer,
  ["landing-featured-trades"],
  {
    revalidate: LANDING_FEATURED_TRADES_REVALIDATE_SECONDS,
    tags: ["landing-featured-trades"],
  }
)

export const getCachedLandingWeeklyTopTraders = unstable_cache(
  fetchWeeklyTopPerformersServer,
  ["landing-weekly-top-traders"],
  {
    revalidate: LANDING_WEEKLY_TOP_TRADERS_REVALIDATE_SECONDS,
    tags: ["landing-weekly-top-traders"],
  }
)
