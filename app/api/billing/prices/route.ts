import { publicTraxProPriceResponse } from "@/lib/traxProPriceCatalog"
import { loadTraxProStripePriceCatalog } from "@/lib/traxProPriceCatalog.server"

export const runtime = "nodejs"

/** Public TraxPro amounts from the configured Stripe Prices. Secrets stay on the server. */
export async function GET() {
  try {
    const catalog = await loadTraxProStripePriceCatalog()
    return Response.json(publicTraxProPriceResponse(catalog))
  } catch (error) {
    console.error("[billing/prices]", error)
    return Response.json(
      {
        ok: false,
        error: "Couldn't load Stripe plans right now.",
      },
      { status: 503 }
    )
  }
}
