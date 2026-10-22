import { getCachedLandingWeeklyTopTraders } from "@/lib/landingServerData"
import LandingWeeklyTopTradersSection from "./LandingWeeklyTopTradersSection"

/** Server loader — cached weekly top traders revalidate on 30-minute schedule. */
export default async function LandingWeeklyTopTradersSectionLoader() {
  const payload = await getCachedLandingWeeklyTopTraders()
  return <LandingWeeklyTopTradersSection initialPayload={payload} />
}
