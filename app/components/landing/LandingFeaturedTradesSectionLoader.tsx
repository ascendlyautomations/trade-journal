import { getCachedLandingFeaturedTrades } from "@/lib/landingServerData"
import LandingFeaturedTradesSection from "./LandingFeaturedTradesSection"

/** Server loader — cached featured trades revalidate on 30-minute schedule. */
export default async function LandingFeaturedTradesSectionLoader() {
  const featured = await getCachedLandingFeaturedTrades()
  return <LandingFeaturedTradesSection initialFeatured={featured} />
}
