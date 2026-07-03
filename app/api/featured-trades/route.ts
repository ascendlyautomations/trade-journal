import { NextResponse } from "next/server"
import {
  getCachedLandingFeaturedTrades,
  LANDING_FEATURED_TRADES_REVALIDATE_SECONDS,
} from "@/lib/landingServerData"

export async function GET() {
  const response = await getCachedLandingFeaturedTrades()

  return NextResponse.json(response, {
    headers: {
      "Cache-Control": `public, s-maxage=${LANDING_FEATURED_TRADES_REVALIDATE_SECONDS}, stale-while-revalidate=${LANDING_FEATURED_TRADES_REVALIDATE_SECONDS * 2}`,
    },
  })
}
